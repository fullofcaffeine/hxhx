(* OCaml runtime implementation for the Haxe `EReg` API.

   Strategy (M11):
   - Use OCaml's standard `Str` library to avoid external dependencies.
   - Translate the most common Haxe/PCRE-ish regex syntax into `Str`'s Emacs-style
     regex syntax at construction time.

   Positions:
   - `Str` works on UTF-8 bytes, but a Haxe `String` counts Unicode code points.
     Stored match offsets stay in bytes; `matchedPos` and `matchSub` convert at
     the Haxe boundary with the `HxString` layout helpers. For example, after
     `~/b/` matches "éb", `matchedPos().pos` is 1, so `"éb".substr(1)` is "b".
   - `matchSub` deliberately reads `pos` and `len` as code points. Upstream eval
     reads them as bytes while its `matchedPos` returns code points, so feeding
     one into the other loops forever there (haxe_ocaml-4aoh2).

   Important limitations:
   - This is not a full PCRE implementation.
   - Matching itself is still byte-wise: `.` and character classes can match one
     byte of a multi-byte character (haxe_ocaml-1w6os).
   - Advanced constructs like lookahead/lookbehind, named groups, and many
     unicode character classes are not supported.
   - When an unsupported pattern is used, behavior is "best effort" and may
     raise at runtime.
*)

type match_result =
  { src : string
  ; groups : (int * int) array
  }

type t =
  { re : Str.regexp
  ; global : bool
  ; mutable last : match_result option
  }

let is_global (opt : string) : bool =
  let rec loop i =
    if i >= Stdlib.String.length opt then false
    else if (Stdlib.String.get opt (i)) = 'g' then true
    else loop (i + 1)
  in
  loop 0

let is_casefold (opt : string) : bool =
  let rec loop i =
    if i >= Stdlib.String.length opt then false
    else if (Stdlib.String.get opt (i)) = 'i' then true
    else loop (i + 1)
  in
  loop 0

let translate_pattern (p : string) : string =
  (* Translate common PCRE-ish constructs to OCaml Str (Emacs) syntax. *)
  let buf = Buffer.create (Stdlib.String.length p * 2) in
  let len = Stdlib.String.length p in
  let rec loop i in_class =
    if i >= len then ()
    else
      let c = (Stdlib.String.get p (i)) in
      if c = '\\' && i + 1 < len then (
        let n = (Stdlib.String.get p (i + 1)) in
        (* PCRE escapes we can map. *)
        (match n with
        | 'd' -> Buffer.add_string buf "[0-9]"
        | 'D' -> Buffer.add_string buf "[^0-9]"
        | 'w' -> Buffer.add_string buf "[A-Za-z0-9_]"
        | 'W' -> Buffer.add_string buf "[^A-Za-z0-9_]"
        | 's' -> Buffer.add_string buf "[ \t\r\n]"
        | 'S' -> Buffer.add_string buf "[^ \t\r\n]"
        (* PCRE escapes for literals. Note: Str treats `+` and `?` as operators
           by default, so keep their escapes to preserve literal meaning. *)
        | '(' | ')' | '|' | '{' | '}' -> Buffer.add_char buf n
        | '+' | '?' ->
            Buffer.add_char buf '\\';
            Buffer.add_char buf n
        | _ ->
            Buffer.add_char buf '\\';
            Buffer.add_char buf n);
        loop (i + 2) in_class)
      else (
        let next_in_class =
          if (not in_class) && c = '[' then true
          else if in_class && c = ']' then false
          else in_class
        in
        if (not in_class)
           && (c = '|' || c = '{' || c = '}' || c = '(' || c = ')')
        then (
          (* Str requires backslash escapes for these operators. *)
          Buffer.add_char buf '\\';
          Buffer.add_char buf c)
        else Buffer.add_char buf c;
        loop (i + 1) next_in_class)
  in
  loop 0 false;
  Buffer.contents buf

let create (r : string) (opt : string) : t =
  let pat = translate_pattern r in
  let re = if is_casefold opt then Str.regexp_case_fold pat else Str.regexp pat in
  { re; global = is_global opt; last = None }

let collect_groups () : (int * int) array =
  (* Group 0 is the whole match; subsequent groups follow. *)
  let rec loop i acc =
    try
      let b = Str.group_beginning i in
      let e = Str.group_end i in
      loop (i + 1) ((b, e) :: acc)
    with _ ->
      Stdlib.Array.of_list (Stdlib.List.rev acc)
  in
  loop 0 []

let set_last (self : t) (src : string) : unit =
  let groups = collect_groups () in
  self.last <- Some { src; groups }

let hx_match (self : t) (s : string) : bool =
  try
    ignore (Str.search_forward self.re s 0);
    set_last self s;
    true
  with Not_found ->
    self.last <- None;
    false

let matchSub (self : t) (s : string) (pos : int) (len : int) : bool =
  (* Optional `Int` parameters can be padded with `hx_null` by the backend to
     avoid partial application. Normalize that sentinel to the Haxe default
     (`-1`) before doing integer arithmetic. *)
  let len =
    let raw : Obj.t = Obj.magic len in
    if raw == HxRuntime.hx_null then -1 else len
  in
  let l = HxString.layout s in
  (* A position past the text raises, as Str does for a bad byte offset. *)
  if pos < 0 || pos > l.HxString.count then invalid_arg "EReg.matchSub";
  let start = HxString.byte_offset l pos in
  let limit =
    if len < 0 then Stdlib.String.length s
    else min (Stdlib.String.length s) (HxString.byte_offset l (pos + len))
  in
  try
    ignore (Str.search_forward self.re s start);
    let e = Str.group_end 0 in
    if e <= limit then (
      set_last self s;
      true)
    else (
      self.last <- None;
      false)
  with Not_found ->
    self.last <- None;
    false

let matched (self : t) (n : int) : string =
  match self.last with
  | None -> ""
  | Some st ->
      if n < 0 || n >= Stdlib.Array.length st.groups then ""
      else
        let b, e = Stdlib.Array.get st.groups n in
        if b < 0 || e < b then "" else Stdlib.String.sub st.src b (e - b)

let matchedLeft (self : t) () : string =
  match self.last with
  | None -> ""
  | Some st ->
      if Stdlib.Array.length st.groups = 0 then ""
      else
        let b, _ = Stdlib.Array.get st.groups 0 in
        if b <= 0 then "" else Stdlib.String.sub st.src 0 b

let matchedRight (self : t) () : string =
  match self.last with
  | None -> ""
  | Some st ->
      if Stdlib.Array.length st.groups = 0 then ""
      else
        let _, e = Stdlib.Array.get st.groups 0 in
        if e >= Stdlib.String.length st.src then ""
        else Stdlib.String.sub st.src e (Stdlib.String.length st.src - e)

(* Code-point index for a byte offset that Str reported. Byte-wise matching can
   end inside a multi-byte character, where `HxString.index_of_byte` answers -1.
   [step] moves to the nearest character boundary: -1 for the character holding
   the offset, 1 for the one after it. *)
let rec code_point_near (l : HxString.layout) (b : int) (step : int) : int =
  let i = HxString.index_of_byte l b in
  if i >= 0 then i else code_point_near l (b + step) step

let matchedPos (self : t) () : Obj.t =
  match self.last with
  | None -> HxRuntime.hx_null
  | Some st ->
      if Stdlib.Array.length st.groups = 0 then HxRuntime.hx_null
      else
        let b, e = Stdlib.Array.get st.groups 0 in
        let l = HxString.layout st.src in
        let first = code_point_near l b (-1) in
        let after = if e = b then first else code_point_near l e 1 in
        let o = HxAnon.create () in
        ignore (HxAnon.set o "pos" (Obj.repr first));
        ignore (HxAnon.set o "len" (Obj.repr (after - first)));
        o

let split (self : t) (s : string) : string HxArray.t =
  let out = HxArray.create () in
  let len_s = Stdlib.String.length s in
  let rec loop from =
    try
      ignore (Str.search_forward self.re s from);
      let b = Str.group_beginning 0 in
      let e = Str.group_end 0 in
      ignore (HxArray.push out (Stdlib.String.sub s from (b - from)));
      if self.global then (
        let next = if e = b then min len_s (e + 1) else e in
        if next <= len_s then loop next else ())
      else (
        ignore (HxArray.push out (Stdlib.String.sub s e (len_s - e)));
        raise Exit)
    with
    | Not_found ->
        ignore (HxArray.push out (Stdlib.String.sub s from (len_s - from)))
    | Exit -> ()
  in
  loop 0;
  out

let expand_replacement (self : t) (by : string) : string =
  let buf = Buffer.create (Stdlib.String.length by + 16) in
  let len = Stdlib.String.length by in
  let rec loop i =
    if i >= len then ()
    else
      let c = (Stdlib.String.get by (i)) in
      if c = '$' && i + 1 < len then (
        let n = (Stdlib.String.get by (i + 1)) in
        (match n with
        | '$' ->
            Buffer.add_char buf '$';
            loop (i + 2)
        | '0' .. '9' ->
            let idx = Char.code n - Char.code '0' in
            Buffer.add_string buf (matched self idx);
            loop (i + 2)
        | _ ->
            Buffer.add_char buf '$';
            loop (i + 1));
        ())
      else (
        Buffer.add_char buf c;
        loop (i + 1))
  in
  loop 0;
  Buffer.contents buf

let replace (self : t) (s : string) (by : string) : string =
  let len_s = Stdlib.String.length s in
  let buf = Buffer.create (len_s + 32) in
  let rec loop from =
    try
      ignore (Str.search_forward self.re s from);
      set_last self s;
      let b = Str.group_beginning 0 in
      let e = Str.group_end 0 in
      Buffer.add_string buf (Stdlib.String.sub s from (b - from));
      Buffer.add_string buf (expand_replacement self by);
      if self.global then (
        let next = if e = b then min len_s (e + 1) else e in
        if next <= len_s then loop next else ())
      else Buffer.add_string buf (Stdlib.String.sub s e (len_s - e))
    with Not_found ->
      Buffer.add_string buf (Stdlib.String.sub s from (len_s - from))
  in
  loop 0;
  Buffer.contents buf

let map (self : t) (s : string) (f : t -> string) : string =
  let len_s = Stdlib.String.length s in
  let buf = Buffer.create (len_s + 32) in
  let rec loop from =
    try
      ignore (Str.search_forward self.re s from);
      set_last self s;
      let b = Str.group_beginning 0 in
      let e = Str.group_end 0 in
      Buffer.add_string buf (Stdlib.String.sub s from (b - from));
      Buffer.add_string buf (f self);
      if self.global then (
        let next = if e = b then min len_s (e + 1) else e in
        if next <= len_s then loop next else ())
      else Buffer.add_string buf (Stdlib.String.sub s e (len_s - e))
    with Not_found ->
      Buffer.add_string buf (Stdlib.String.sub s from (len_s - from))
  in
  loop 0;
  Buffer.contents buf

let escape (s : string) : string =
  (* Escape common metacharacters for inclusion in a Haxe regex literal. *)
  let buf = Buffer.create (Stdlib.String.length s * 2) in
  let is_meta = function
    | '\\' | '.' | '+' | '*' | '?' | '^' | '$' | '(' | ')' | '[' | ']' | '{'
    | '}' | '|' ->
        true
    | _ -> false
  in
  Stdlib.String.iter
    (fun c ->
      if is_meta c then Buffer.add_char buf '\\';
      Buffer.add_char buf c)
    s;
  Buffer.contents buf
