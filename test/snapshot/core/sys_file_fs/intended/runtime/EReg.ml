(* OCaml runtime implementation for the Haxe `EReg` API.

   What callers can rely on
   - Every position is a Unicode code-point index, as in upstream Haxe 4.3.7
     eval and as in the `HxString` String API. With s = "héllo", `~/l+/`
     reports `matchedPos` = {pos = 2; len = 2}, so `s.substr(r.matchedPos().pos)`
     starts at the first "l".
   - `matchSub` reads its position and length as code points too. Upstream eval
     reads them as bytes while `matchedPos` returns code points; this runtime
     keeps one coordinate system (see docs/02-user-guide/EREG_STRATEGY.md).
   - `.`, a character class, and a quantified non-ASCII literal match one whole
     character. `i` folds ASCII letters and non-ASCII characters with Unicode
     simple case mapping (the `HxString` case tables).
   - An empty global match steps over one whole character.

   How
   Matching uses OCaml's byte-based `Str` library. A Haxe (PCRE-style) pattern
   is translated into `Str` syntax in one of two modes:
   - ASCII mode, for subjects that are pure ASCII. Non-ASCII parts of the
     pattern cannot match there, `i` uses `Str.regexp_case_fold`, and byte
     positions already are code-point positions.
   - UTF-8 mode, compiled the first time a subject contains a non-ASCII byte.
     `.` and every class become a code-point set rendered as UTF-8 byte
     sequences; quantified multi-byte atoms are wrapped in a `Str` group; `i`
     is folded into the pattern itself, because `Str`'s folding table is
     Latin-1 and would treat the UTF-8 lead bytes 0xC3 and 0xE3 as one letter.
   Inserted groups shift `Str`'s group numbers, so each translation carries a
   map from Haxe group numbers to `Str` group numbers. The same map makes
   `(?:...)` non-capturing groups work.

   Matches are found and stored as byte offsets. They are converted to code
   points only where Haxe sees a position, with the `HxString` layout helpers;
   `matched`, `matchedLeft`, `split`, `replace` and `map` slice bytes at
   character boundaries.

   Known limitations: `{m,n}`, lazy quantifiers (matched greedily),
   lookaround, named groups, `\B`, Unicode properties for `\w` `\d` `\s` `\b`
   (ASCII only here), and PCRE `^`/`$` (here they always match at line
   boundaries). Unsupported group syntax such as `(?=...)` raises `Failure`
   when the EReg is created. *)

type match_result =
  { src : string
  ; groups : (int * int) array (* byte offsets per Haxe group; (-1, -1) when unmatched *)
  }

type compiled =
  { re : Str.regexp
  ; group_map : int array (* Haxe group number -> Str group number *)
  }

type t =
  { pattern : int array (* code points of the Haxe pattern *)
  ; global : bool
  ; casefold : bool
  ; dotall : bool
  ; ascii_mode : compiled
  ; mutable utf8_mode : compiled option
  ; mutable last : match_result option
  }

(* ---- Code-point sets ----------------------------------------------------

   A set is a sorted list of disjoint, non-adjacent inclusive intervals. *)

let max_code = 0x10FFFF

let normalize (ranges : (int * int) list) : (int * int) list =
  let sorted = Stdlib.List.sort compare ranges in
  let rec merge acc = function
    | [] -> Stdlib.List.rev acc
    | (lo, hi) :: rest -> (
        match acc with
        | (plo, phi) :: acc_rest when lo <= phi + 1 -> merge ((plo, max phi hi) :: acc_rest) rest
        | _ -> merge ((lo, hi) :: acc) rest)
  in
  merge [] sorted

let complement (set : (int * int) list) : (int * int) list =
  let rec loop next acc = function
    | [] -> Stdlib.List.rev (if next <= max_code then (next, max_code) :: acc else acc)
    | (lo, hi) :: rest ->
        let acc = if lo > next then (next, lo - 1) :: acc else acc in
        loop (hi + 1) acc rest
  in
  loop 0 [] set

let digit_set = [ (0x30, 0x39) ]
let word_set = [ (0x30, 0x39); (0x41, 0x5A); (0x5F, 0x5F); (0x61, 0x7A) ]
let space_set = [ (0x09, 0x0D); (0x20, 0x20) ]

(* Simple case mapping of one code point, using the String runtime's tables.
   A mapping that would produce more than one character is ignored, as in
   PCRE caseless matching. *)
let map_case (convert : string -> unit -> string) (code : int) : int =
  let mapped = convert (HxString.fromCharCode code) () in
  if HxString.length mapped = 1 then HxString.cca mapped 0 else code

let case_variants (code : int) : (int * int) list =
  let upper = map_case HxString.toUpperCase code in
  let lower = map_case HxString.toLowerCase code in
  let others = [ code; upper; lower; map_case HxString.toLowerCase upper; map_case HxString.toUpperCase lower ] in
  Stdlib.List.map (fun c -> (c, c)) others

(* Sets larger than this are left unfolded: such ranges are rare in patterns
   and enumerating them would make compilation slow. *)
let fold_limit = 0x3000

let fold_set (set : (int * int) list) : (int * int) list =
  let total = Stdlib.List.fold_left (fun n (lo, hi) -> n + hi - lo + 1) 0 set in
  if total > fold_limit then set
  else
    let folded = ref set in
    Stdlib.List.iter
      (fun (lo, hi) ->
        for c = lo to hi do
          folded := Stdlib.List.rev_append (case_variants c) !folded
        done)
      set;
    normalize !folded

(* ASCII-only folding, for ASCII mode, where only ASCII text is matched. *)
let fold_ascii (set : (int * int) list) : (int * int) list =
  let letters (lo, hi) base other =
    let lo = max lo base and hi = min hi (base + 25) in
    if lo > hi then [] else [ (lo - base + other, hi - base + other) ]
  in
  normalize (Stdlib.List.concat_map (fun r -> (r :: letters r 0x41 0x61) @ letters r 0x61 0x41) set)

(* ---- Rendering sets as Str syntax ---------------------------------------- *)

(* A Str character class matching exactly the given bytes (0..255). `]` goes
   first, `^` never first, and `-` first or last, so none of them is read as
   class syntax. *)
let render_byte_class (bytes : (int * int) list) : string =
  let has b = Stdlib.List.exists (fun (lo, hi) -> lo <= b && b <= hi) bytes in
  let close = Stdlib.Char.code ']' and dash = Stdlib.Char.code '-' and caret = Stdlib.Char.code '^' in
  let has_close = has close and has_dash = has dash and has_caret = has caret in
  let buf = Stdlib.Buffer.create 16 in
  Stdlib.Buffer.add_char buf '[';
  if has_close then Stdlib.Buffer.add_char buf ']' else if has_dash then Stdlib.Buffer.add_char buf '-';
  let flush lo hi =
    Stdlib.Buffer.add_char buf (Stdlib.Char.chr lo);
    if hi > lo then (
      if hi > lo + 1 then Stdlib.Buffer.add_char buf '-';
      Stdlib.Buffer.add_char buf (Stdlib.Char.chr hi))
  in
  Stdlib.List.iter
    (fun (lo, hi) ->
      let start = ref (-1) in
      for b = lo to hi do
        if b = close || b = dash || b = caret then (
          if !start >= 0 then flush !start (b - 1);
          start := -1)
        else if !start < 0 then start := b
      done;
      if !start >= 0 then flush !start hi)
    bytes;
  if has_caret then Stdlib.Buffer.add_char buf '^';
  if has_close && has_dash then Stdlib.Buffer.add_char buf '-';
  Stdlib.Buffer.add_char buf ']';
  Stdlib.Buffer.contents buf

let never_matches = "[^\000-\255]"

let render_bytes (bytes : (int * int) list) : string =
  match bytes with
  | [] -> never_matches
  | [ (lo, hi) ] when lo = hi -> Str.quote (Stdlib.String.make 1 (Stdlib.Char.chr lo))
  | _ -> render_byte_class bytes

let utf8_bytes (code : int) : int list =
  if code < 0x80 then [ code ]
  else if code < 0x800 then [ 0xC0 lor (code lsr 6); 0x80 lor (code land 0x3F) ]
  else if code < 0x10000 then [ 0xE0 lor (code lsr 12); 0x80 lor ((code lsr 6) land 0x3F); 0x80 lor (code land 0x3F) ]
  else
    [ 0xF0 lor (code lsr 18)
    ; 0x80 lor ((code lsr 12) land 0x3F)
    ; 0x80 lor ((code lsr 6) land 0x3F)
    ; 0x80 lor (code land 0x3F)
    ]

(* Byte-range sequences matching the UTF-8 encodings of every code point
   between the encodings [lo] and [hi], which have the same length. Each
   sequence holds one inclusive byte range per encoded byte. *)
let rec byte_sequences (lo : int list) (hi : int list) : (int * int) list list =
  match (lo, hi) with
  | [ l ], [ h ] -> [ [ (l, h) ] ]
  | l :: lo_rest, h :: hi_rest ->
      if l = h then Stdlib.List.map (fun seq -> (l, l) :: seq) (byte_sequences lo_rest hi_rest)
      else
        let width = Stdlib.List.length lo_rest in
        let lowest = Stdlib.List.init width (fun _ -> 0x80) in
        let highest = Stdlib.List.init width (fun _ -> 0xBF) in
        let lo_full = lo_rest = lowest and hi_full = hi_rest = highest in
        let first = if lo_full then [] else Stdlib.List.map (fun seq -> (l, l) :: seq) (byte_sequences lo_rest highest) in
        let middle_lo = if lo_full then l else l + 1 in
        let middle_hi = if hi_full then h else h - 1 in
        let middle =
          if middle_lo <= middle_hi then [ (middle_lo, middle_hi) :: Stdlib.List.map (fun _ -> (0x80, 0xBF)) lowest ] else []
        in
        let last = if hi_full then [] else Stdlib.List.map (fun seq -> (h, h) :: seq) (byte_sequences lowest hi_rest) in
        first @ middle @ last
  | _ -> []

let non_ascii_sequences (set : (int * int) list) : string list =
  let bands = [ (0x80, 0x7FF); (0x800, 0xFFFF); (0x10000, max_code) ] in
  Stdlib.List.concat_map
    (fun (lo, hi) ->
      Stdlib.List.concat_map
        (fun (band_lo, band_hi) ->
          let lo = max lo band_lo and hi = min hi band_hi in
          if lo > hi then []
          else
            Stdlib.List.map
              (fun seq -> Stdlib.String.concat "" (Stdlib.List.map (fun range -> render_bytes [ range ]) seq))
              (byte_sequences (utf8_bytes lo) (utf8_bytes hi)))
        bands)
    set

(* ---- Translation --------------------------------------------------------- *)

type translator =
  { utf8 : bool
  ; casefold : bool
  ; fold : bool (* fold literals in the pattern itself (UTF-8 mode with `i`) *)
  ; buf : Stdlib.Buffer.t
  ; mutable str_groups : int
  ; mutable haxe_groups : int list (* Str group of each Haxe group, newest first *)
  }

(* The atom a postfix operator would apply to, by its start in the buffer. A
   unit takes the operator directly; a sequence (such as the two bytes of "é")
   must be wrapped in a group first. *)
type atom =
  | No_atom
  | Unit
  | Sequence of int
  | Any_non_ascii of int * (int * int) list
      (* A set holding every non-ASCII character plus these ASCII ranges. *)

let emit_set (tr : translator) (set : (int * int) list) : atom =
  let start = Stdlib.Buffer.length tr.buf in
  let ascii = Stdlib.List.filter_map (fun (lo, hi) -> if lo > 0x7F then None else Some (lo, min hi 0x7F)) set in
  let non_ascii = Stdlib.List.filter_map (fun (lo, hi) -> if hi < 0x80 then None else Some (max lo 0x80, hi)) set in
  if (not tr.utf8) || non_ascii = [] then (
    Stdlib.Buffer.add_string tr.buf (render_bytes ascii);
    Unit)
  else if non_ascii = [ (0x80, max_code) ] then (
    (* Any non-ASCII character: a lead byte, then its continuation bytes. *)
    Stdlib.Buffer.add_string tr.buf (render_byte_class (ascii @ [ (0xC0, 0xFF) ]));
    Stdlib.Buffer.add_string tr.buf "[\128-\191]*";
    Any_non_ascii (start, ascii))
  else (
    let alternatives = (if ascii = [] then [] else [ render_bytes ascii ]) @ non_ascii_sequences non_ascii in
    Stdlib.Buffer.add_string tr.buf "\\(";
    Stdlib.Buffer.add_string tr.buf (Stdlib.String.concat "\\|" alternatives);
    Stdlib.Buffer.add_string tr.buf "\\)";
    tr.str_groups <- tr.str_groups + 1;
    Unit)

let emit_literal (tr : translator) (code : int) : atom =
  if tr.fold then emit_set tr (fold_set [ (code, code) ])
  else
    let start = Stdlib.Buffer.length tr.buf in
    Stdlib.Buffer.add_string tr.buf (Str.quote (HxString.fromCharCode code));
    if code < 0x80 then Unit else Sequence start

let hex_value (code : int) : int =
  if code >= 0x30 && code <= 0x39 then code - 0x30
  else if code >= 0x61 && code <= 0x66 then code - 0x61 + 10
  else if code >= 0x41 && code <= 0x46 then code - 0x41 + 10
  else -1

type escaped =
  | Set of (int * int) list
  | Code of int

let code (c : char) : int = Stdlib.Char.code c

(* The item escaped by the backslash at [i - 1]: a set or one code point, and
   the index after it. *)
let read_escape (p : int array) (i : int) (in_class : bool) : escaped * int =
  let n = Stdlib.Array.length p in
  let c = (Stdlib.Array.get p (i)) in
  match if c < 0x80 then Stdlib.Char.chr c else '\000' with
  | 'd' -> (Set digit_set, i + 1)
  | 'D' -> (Set (complement digit_set), i + 1)
  | 'w' -> (Set word_set, i + 1)
  | 'W' -> (Set (complement word_set), i + 1)
  | 's' -> (Set space_set, i + 1)
  | 'S' -> (Set (complement space_set), i + 1)
  | 'n' -> (Code 0x0A, i + 1)
  | 'r' -> (Code 0x0D, i + 1)
  | 't' -> (Code 0x09, i + 1)
  | 'f' -> (Code 0x0C, i + 1)
  | 'v' -> (Code 0x0B, i + 1)
  | 'e' -> (Code 0x1B, i + 1)
  | 'b' when in_class -> (Code 0x08, i + 1)
  | 'x' when i + 1 < n && (Stdlib.Array.get p (i + 1)) = code '{' ->
      let j = ref (i + 2) and value = ref 0 in
      while !j < n && hex_value (Stdlib.Array.get p (!j)) >= 0 && !value <= max_code do
        value := (!value * 16) + hex_value (Stdlib.Array.get p (!j));
        incr j
      done;
      if !j < n && (Stdlib.Array.get p (!j)) = code '}' && !value <= max_code then (Code !value, !j + 1)
      else failwith "EReg: malformed \\x{...} escape"
  | 'x' ->
      let j = ref (i + 1) and value = ref 0 in
      while !j < n && !j < i + 3 && hex_value (Stdlib.Array.get p (!j)) >= 0 do
        value := (!value * 16) + hex_value (Stdlib.Array.get p (!j));
        incr j
      done;
      (Code !value, !j)
  | _ -> (Code c, i + 1)

(* The members of the class whose `[` is at [i - 1], whether it is negated,
   and the index after its `]`. *)
let read_class (p : int array) (i : int) : (int * int) list * bool * int =
  let n = Stdlib.Array.length p in
  let negated = i < n && (Stdlib.Array.get p (i)) = code '^' in
  let i = if negated then i + 1 else i in
  let members = ref [] in
  let read_item j = if (Stdlib.Array.get p (j)) = code '\\' && j + 1 < n then read_escape p (j + 1) true else (Code (Stdlib.Array.get p (j)), j + 1) in
  let rec loop j first =
    if j >= n then failwith "EReg: missing ] in character class"
    else if (Stdlib.Array.get p (j)) = code ']' && not first then j + 1
    else
      match read_item j with
      | Set set, next ->
          members := set @ !members;
          loop next false
      | Code lo, next ->
          if next + 1 < n && (Stdlib.Array.get p (next)) = code '-' && (Stdlib.Array.get p (next + 1)) <> code ']' then (
            match read_item (next + 1) with
            | Code hi, after when hi >= lo ->
                members := (lo, hi) :: !members;
                loop after false
            | Code _, _ -> failwith "EReg: character class range out of order"
            | Set set, after ->
                members := ((lo, lo) :: (code '-', code '-') :: set) @ !members;
                loop after false)
          else (
            members := (lo, lo) :: !members;
            loop next false)
  in
  let after = loop i true in
  (normalize !members, negated, after)

let translate ~(utf8 : bool) ~(casefold : bool) ~(dotall : bool) (p : int array) : string * int array =
  let tr = { utf8; casefold; fold = utf8 && casefold; buf = Stdlib.Buffer.create (Stdlib.Array.length p * 2); str_groups = 0; haxe_groups = [] } in
  let n = Stdlib.Array.length p in
  let dot = if dotall then [ (0, max_code) ] else complement [ (0x0A, 0x0A) ] in
  let open_groups = ref 0 in
  let rec loop i (atom : atom) =
    if i < n then
      let c = (Stdlib.Array.get p (i)) in
      match if c < 0x80 then Stdlib.Char.chr c else '\000' with
      | '\\' when i + 1 < n ->
          let next = (Stdlib.Array.get p (i + 1)) in
          if next >= code '1' && next <= code '9' then (
            let groups = Stdlib.List.rev tr.haxe_groups in
            let haxe = next - code '0' in
            if haxe > Stdlib.List.length groups then failwith "EReg: back reference to an unknown group";
            let str = Stdlib.List.nth groups (haxe - 1) in
            if str > 9 then failwith "EReg: back reference needs more than 9 internal groups";
            Stdlib.Buffer.add_string tr.buf ("\\" ^ string_of_int str);
            loop (i + 2) Unit)
          else if next = code 'b' then (
            Stdlib.Buffer.add_string tr.buf "\\b";
            loop (i + 2) No_atom)
          else
            let item, after = read_escape p (i + 1) false in
            loop after (match item with Set set -> emit_set tr set | Code c -> emit_literal tr c)
      | '.' -> loop (i + 1) (emit_set tr dot)
      | '[' ->
          (* Fold the members before negating: `[^a]` with `i` excludes `A` too. *)
          let members, negated, after = read_class p (i + 1) in
          let members = if not casefold then members else if utf8 then fold_set members else fold_ascii members in
          loop after (emit_set tr (if negated then complement members else members))
      | '(' ->
          let after =
            if i + 1 < n && (Stdlib.Array.get p (i + 1)) = code '?' then
              if i + 2 < n && (Stdlib.Array.get p (i + 2)) = code ':' then i + 3
              else failwith "EReg: unsupported group syntax (lookaround, named groups and inline flags)"
            else (
              tr.haxe_groups <- (tr.str_groups + 1) :: tr.haxe_groups;
              i + 1)
          in
          Stdlib.Buffer.add_string tr.buf "\\(";
          tr.str_groups <- tr.str_groups + 1;
          incr open_groups;
          loop after No_atom
      | ')' when !open_groups > 0 ->
          decr open_groups;
          Stdlib.Buffer.add_string tr.buf "\\)";
          loop (i + 1) Unit
      | '|' ->
          Stdlib.Buffer.add_string tr.buf "\\|";
          loop (i + 1) No_atom
      | ('^' | '$') as ch ->
          Stdlib.Buffer.add_char tr.buf ch;
          loop (i + 1) No_atom
      | ('*' | '+' | '?') as ch when atom <> No_atom ->
          (match (atom, ch) with
          | Any_non_ascii (start, ascii), ('*' | '+') ->
              (* Repeat bytes instead of a group of characters, which Str
                 matches much faster. Every atom that can follow starts with a
                 non-continuation byte, and [search] rejects a match that ends
                 inside a character, so the repetition still ends on a
                 character boundary. *)
              let bytes = render_byte_class (ascii @ [ (0x80, 0xFF) ]) in
              Stdlib.Buffer.truncate tr.buf start;
              if ch = '+' then Stdlib.Buffer.add_string tr.buf (render_byte_class (ascii @ [ (0xC0, 0xFF) ]));
              Stdlib.Buffer.add_string tr.buf bytes
          | (Sequence start | Any_non_ascii (start, _)), _ ->
              (* Wrap the multi-byte atom so the operator repeats all of it. A
                 leaf atom opens no group, so earlier numbers stay valid. *)
              let tail = Stdlib.Buffer.sub tr.buf start (Stdlib.Buffer.length tr.buf - start) in
              Stdlib.Buffer.truncate tr.buf start;
              Stdlib.Buffer.add_string tr.buf ("\\(" ^ tail ^ "\\)");
              tr.str_groups <- tr.str_groups + 1
          | _ -> ());
          (match (atom, ch) with Any_non_ascii _, ('*' | '+') -> Stdlib.Buffer.add_char tr.buf '*' | _ -> Stdlib.Buffer.add_char tr.buf ch);
          (* A lazy (`*?`) or possessive (`*+`) marker is accepted and matched greedily. *)
          let marked = i + 1 < n && ((Stdlib.Array.get p (i + 1)) = code '?' || (Stdlib.Array.get p (i + 1)) = code '+') in
          loop (if marked then i + 2 else i + 1) No_atom
      | _ -> loop (i + 1) (emit_literal tr c)
  in
  loop 0 No_atom;
  (Stdlib.Buffer.contents tr.buf, Stdlib.Array.of_list (0 :: Stdlib.List.rev tr.haxe_groups))

(* ---- Construction -------------------------------------------------------- *)

let compile ~(utf8 : bool) ~(casefold : bool) ~(dotall : bool) (p : int array) : compiled =
  let source, group_map = translate ~utf8 ~casefold ~dotall p in
  let re = if casefold && not utf8 then Str.regexp_case_fold source else Str.regexp source in
  { re; group_map }

let create (r : string) (opt : string) : t =
  let pattern = Stdlib.Array.init (HxString.length r) (fun i -> HxString.cca r i) in
  let casefold = Stdlib.String.contains opt 'i' and dotall = Stdlib.String.contains opt 's' in
  { pattern
  ; global = Stdlib.String.contains opt 'g'
  ; casefold
  ; dotall
  ; ascii_mode = compile ~utf8:false ~casefold ~dotall pattern
  ; utf8_mode = None
  ; last = None
  }

let compiled_for (self : t) (l : HxString.layout) : compiled =
  if l.HxString.ascii then self.ascii_mode
  else
    match self.utf8_mode with
    | Some c -> c
    | None ->
        let c = compile ~utf8:true ~casefold:self.casefold ~dotall:self.dotall self.pattern in
        self.utf8_mode <- Some c;
        c

(* ---- Matching ------------------------------------------------------------ *)

(* Only a continuation byte (0x80-0xBF) can sit inside a character, so other
   bytes skip the layout lookup. *)
let on_boundary (l : HxString.layout) (s : string) (b : int) : bool =
  l.HxString.ascii
  || b >= Stdlib.String.length s
  || (let byte = Stdlib.Char.code (Stdlib.String.unsafe_get s b) in
      byte < 0x80 || byte >= 0xC0)
  || HxString.index_of_byte l b >= 0

(* Start of the leftmost match at or after byte [from] that begins and ends on
   character boundaries; Str's match registers then describe that match. *)
let search (c : compiled) (s : string) (l : HxString.layout) (from : int) : int option =
  let len = Stdlib.String.length s in
  let rec go from =
    match Str.search_forward c.re s from with
    | b -> if on_boundary l s b && on_boundary l s (Str.match_end ()) then Some b else if b < len then go (b + 1) else None
    | exception Not_found -> None
  in
  if from > len then None else go from

let capture (c : compiled) (src : string) : match_result =
  let groups =
    Stdlib.Array.map (fun str -> try (Str.group_beginning str, Str.group_end str) with Not_found -> (-1, -1)) c.group_map
  in
  { src; groups }

(* Bytes taken by the character at byte [b]; 1 at the end of [s]. *)
let char_width (l : HxString.layout) (s : string) (b : int) : int =
  if l.HxString.ascii || b >= Stdlib.String.length s then 1
  else HxString.byte_offset l (HxString.index_of_byte l b + 1) - b

let hx_match (self : t) (s : string) : bool =
  let l = HxString.layout s in
  let c = compiled_for self l in
  match search c s l 0 with
  | Some _ ->
      self.last <- Some (capture c s);
      true
  | None ->
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
  let count = l.HxString.count in
  let len = if len < 0 then count - pos else len in
  if pos < 0 || pos > count || pos + len > count then false
  else
    (* As upstream does, search only the window [0, pos + len): a match cannot
       run past it, and `$` matches at its end. *)
    let limit = HxString.byte_offset l (pos + len) in
    let window = if limit = Stdlib.String.length s then s else Stdlib.String.sub s 0 limit in
    let wl = if window == s then l else HxString.layout window in
    let c = compiled_for self wl in
    match search c window wl (HxString.byte_offset l pos) with
    | Some _ ->
        self.last <- Some (capture c s);
        true
    | None -> false

let group (self : t) (n : int) : (string * int * int) option =
  match self.last with
  | Some st when n >= 0 && n < Stdlib.Array.length st.groups ->
      let b, e = (Stdlib.Array.get st.groups (n)) in
      if b < 0 then None else Some (st.src, b, e)
  | _ -> None

(* An unmatched group yields null, as upstream does; an unknown group "". *)
let matched (self : t) (n : int) : string =
  match self.last with
  | Some st when n >= 0 && n < Stdlib.Array.length st.groups -> (
      match group self n with Some (src, b, e) -> Stdlib.String.sub src b (e - b) | None -> HxString.hx_null_string)
  | _ -> ""

let matchedLeft (self : t) () : string =
  match group self 0 with Some (src, b, _) -> Stdlib.String.sub src 0 b | None -> ""

let matchedRight (self : t) () : string =
  match group self 0 with Some (src, _, e) -> Stdlib.String.sub src e (Stdlib.String.length src - e) | None -> ""

let matchedPos (self : t) () : Obj.t =
  match group self 0 with
  | None -> HxRuntime.hx_null
  | Some (src, b, e) ->
      let l = HxString.layout src in
      let first = HxString.index_of_byte l b in
      let o = HxAnon.create () in
      ignore (HxAnon.set o "pos" (Obj.repr first));
      ignore (HxAnon.set o "len" (Obj.repr (HxString.index_of_byte l e - first)));
      o

(* Upstream eval's algorithm, including its handling of empty matches, but
   stepping one character instead of one byte. *)
let split (self : t) (s : string) : string HxArray.t =
  let out = HxArray.create () in
  let len_s = Stdlib.String.length s in
  if len_s = 0 then ignore (HxArray.push out "")
  else (
    let l = HxString.layout s in
    let c = compiled_for self l in
    let copy = ref 0 in
    let add first last = ignore (HxArray.push out (Stdlib.String.sub s first (last - first))) in
    let step pos =
      match search c s l pos with
      | Some first ->
          let last = Str.match_end () in
          add !copy first;
          copy := last;
          let next = if pos = last then last + char_width l s last else last in
          if next >= len_s then (
            ignore (HxArray.push out "");
            None)
          else Some next
      | None ->
          add !copy len_s;
          None
    in
    let rec loop pos =
      match step pos with Some next -> if self.global then loop next else add !copy len_s | None -> ()
    in
    loop 0);
  out

(* `$0`..`$9` insert a group (nothing when unmatched) and `$$` inserts `$`. *)
let expand_replacement (self : t) (by : string) (buf : Stdlib.Buffer.t) : unit =
  let len = Stdlib.String.length by in
  let rec loop i =
    if i < len then
      let c = Stdlib.String.get by i in
      if c = '$' && i + 1 < len then (
        match Stdlib.String.get by (i + 1) with
        | '$' ->
            Stdlib.Buffer.add_char buf '$';
            loop (i + 2)
        | '0' .. '9' as d ->
            (match group self (Stdlib.Char.code d - Stdlib.Char.code '0') with
            | Some (src, b, e) -> Stdlib.Buffer.add_substring buf src b (e - b)
            | None -> ());
            loop (i + 2)
        | _ ->
            Stdlib.Buffer.add_char buf '$';
            loop (i + 1))
      else (
        Stdlib.Buffer.add_char buf c;
        loop (i + 1))
  in
  loop 0

let replace (self : t) (s : string) (by : string) : string =
  let len_s = Stdlib.String.length s in
  let buf = Stdlib.Buffer.create (len_s + 32) in
  let l = HxString.layout s in
  let c = compiled_for self l in
  let rec loop pos =
    match search c s l pos with
    | None -> Stdlib.Buffer.add_substring buf s pos (len_s - pos)
    | Some b ->
        let e = Str.match_end () in
        self.last <- Some (capture c s);
        Stdlib.Buffer.add_substring buf s pos (b - pos);
        expand_replacement self by buf;
        if not self.global then Stdlib.Buffer.add_substring buf s e (len_s - e)
        else if e > b then loop e
        else if b < len_s then (
          let w = char_width l s b in
          Stdlib.Buffer.add_substring buf s b w;
          loop (b + w))
  in
  loop 0;
  Stdlib.Buffer.contents buf

(* Upstream eval's algorithm, including its handling of empty matches, but
   stepping one character instead of one byte. *)
let map (self : t) (s : string) (f : t -> string) : string =
  let len_s = Stdlib.String.length s in
  let buf = Stdlib.Buffer.create (len_s + 32) in
  let l = HxString.layout s in
  let c = compiled_for self l in
  let rec loop pos =
    if pos < len_s then
      match search c s l pos with
      | None -> Stdlib.Buffer.add_substring buf s pos (len_s - pos)
      | Some first ->
          let last = Str.match_end () in
          self.last <- Some (capture c s);
          Stdlib.Buffer.add_substring buf s pos (first - pos);
          Stdlib.Buffer.add_string buf (f self);
          if last = first then (
            if last < len_s then
              if self.global then (
                let w = char_width l s first in
                Stdlib.Buffer.add_substring buf s first w;
                loop (first + w))
              else Stdlib.Buffer.add_substring buf s first (len_s - first))
          else if self.global then loop last
          else Stdlib.Buffer.add_substring buf s last (len_s - last)
  in
  loop 0;
  self.last <- None;
  Stdlib.Buffer.contents buf

let escape (s : string) : string =
  (* Escape common metacharacters for inclusion in a Haxe regex literal. *)
  let buf = Stdlib.Buffer.create (Stdlib.String.length s * 2) in
  let is_meta = function
    | '\\' | '.' | '+' | '*' | '?' | '^' | '$' | '(' | ')' | '[' | ']' | '{' | '}' | '|' -> true
    | _ -> false
  in
  Stdlib.String.iter
    (fun c ->
      if is_meta c then Stdlib.Buffer.add_char buf '\\';
      Stdlib.Buffer.add_char buf c)
    s;
  Stdlib.Buffer.contents buf
