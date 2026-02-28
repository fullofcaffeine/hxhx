(* Minimal Haxe String runtime for reflaxe.ocaml (WIP).

   Notes:
   - OCaml strings are byte sequences; this implementation is byte-based and
     intentionally focuses on ASCII-heavy bootstrapping workloads.
   - Some edge cases are "unspecified" in Haxe docs; we choose pragmatic
     behavior that matches most targets. *)

let length (s : string) : int =
  String.length s

let hx_null_string : string = Obj.magic HxRuntime.hx_null

let isNull (s : string) : bool =
  s == hx_null_string

let isRealStringObj (o : Obj.t) : bool =
  not (Obj.is_int o) && Obj.tag o = Obj.string_tag

(* Used for Haxe's `Std.string` semantics and string concatenation.
   - In Haxe, `Std.string(null)` yields "null"
   - In Haxe, `"x" + null` yields "xnull" *)
let toStdString (s : string) : string =
  if isNull s then
    "null"
  else
    s

(* Safe string equality that handles nullable strings without segfaulting.
   OCaml's `=` can compile down to specialized string equality if the type is known
   to be `string`, which assumes both operands are real strings. *)
let equals (a : string) (b : string) : bool =
  let oa : Obj.t = Obj.magic a in
  let ob : Obj.t = Obj.magic b in
  if oa == HxRuntime.hx_null then
    ob == HxRuntime.hx_null
  else if ob == HxRuntime.hx_null then
    false
  else if not (isRealStringObj oa) || not (isRealStringObj ob) then
    false
  else
    String.equal a b

let toUpperCase (s : string) () : string =
  String.uppercase_ascii s

let toLowerCase (s : string) () : string =
  String.lowercase_ascii s

let charAt (s : string) (index : int) : string =
  let len = String.length s in
  if index < 0 || index >= len then
    ""
  else
    String.sub s index 1

(* Haxe: String.charCodeAt returns Null<Int> and yields null on OOB. *)
let charCodeAt (s : string) (index : int) : Obj.t =
  let len = String.length s in
  if index < 0 || index >= len then
    HxRuntime.hx_null
  else
    Obj.repr (Char.code s.[index])

(* `StringTools.fastCodeAt()` uses `untyped s.cca(index)` on a number of targets.
   We represent `String` as a plain OCaml `string`, so there is no real `.cca`
   method to dispatch to. Instead, the backend routes `untyped s.cca(i)` through
   `HxAnon.get (Obj.repr s) "cca"` and we provide a closure from `HxAnon.get`.

   Semantics:
   - Returns `-1` when `index == s.length` (EOF sentinel), matching Haxe's docs.
   - Returns `-1` on any out-of-bounds index. *)
let cca (s : string) (index : int) : int =
  if isNull s then
    -1
  else
    let len = String.length s in
    if index < 0 || index >= len then
      -1
    else
      Char.code s.[index]

let starts_with_at (s : string) (sub : string) (i : int) : bool =
  let slen = String.length s in
  let nlen = String.length sub in
  if i < 0 || i + nlen > slen then
    false
  else
    let rec loop j =
      if j >= nlen then
        true
      else if s.[i + j] = sub.[j] then
        loop (j + 1)
      else
        false
    in
    loop 0

let unwrap_optional_int (v : int) (default : int) : int =
  let raw : Obj.t = Obj.magic v in
  if raw == HxRuntime.hx_null then
    default
  else
    v

let indexOf (s : string) (sub : string) (startIndex : int) : int =
  let slen = String.length s in
  let nlen = String.length sub in
  let startIndex = unwrap_optional_int startIndex 0 in
  if startIndex > slen then
    -1
  else if nlen = 0 then
    if startIndex < 0 then 0 else startIndex
  else (
    let start = if startIndex < 0 then 0 else startIndex in
    let limit = slen - nlen in
    let rec search i =
      if i > limit then
        -1
      else if starts_with_at s sub i then
        i
      else
        search (i + 1)
    in
    search start
  )

let lastIndexOf (s : string) (sub : string) (startIndex : int) : int =
  let slen = String.length s in
  let nlen = String.length sub in
  let startIndex = unwrap_optional_int startIndex slen in
  if nlen = 0 then (
    let idx = if startIndex < 0 then slen else startIndex in
    if idx > slen then slen else idx
  ) else (
    let max_pos = slen - nlen in
    if max_pos < 0 then
      -1
    else (
      let start =
        let idx = if startIndex < 0 then slen else startIndex in
        let clamped = if idx > slen then slen else idx in
        let p = clamped in
        if p > max_pos then max_pos else p
      in
      let rec search i =
        if i < 0 then
          -1
        else if starts_with_at s sub i then
          i
        else
          search (i - 1)
      in
      search start
    )
  )

let split (s : string) (delimiter : string) : string HxArray.t =
  let out = HxArray.create () in
  let slen = String.length s in
  let dlen = String.length delimiter in
  if dlen = 0 then (
    for i = 0 to slen - 1 do
      ignore (HxArray.push out (String.sub s i 1))
    done;
    out
  ) else (
    let rec loop start =
      let idx = indexOf s delimiter start in
      if idx < 0 then (
        ignore (HxArray.push out (String.sub s start (slen - start)));
        out
      ) else (
        ignore (HxArray.push out (String.sub s start (idx - start)));
        loop (idx + dlen)
      )
    in
    loop 0
  )

let substr (s : string) (pos : int) (len : int) : string =
  let slen = String.length s in
  let len = unwrap_optional_int len (-1) in
  let p =
    if pos < 0 then
      let raw = slen + pos in
      if raw < 0 then 0 else raw
    else
      pos
  in
  if p >= slen then
    ""
  else
    let l = if len < 0 then slen - p else len in
    if l <= 0 then
      ""
    else
      let max_len = slen - p in
      let l2 = if l > max_len then max_len else l in
      String.sub s p l2

let substring (s : string) (startIndex : int) (endIndex : int) : string =
  let slen = String.length s in
  let endIndex = unwrap_optional_int endIndex slen in
  let s0 = if startIndex < 0 then 0 else startIndex in
  let e0 =
    if endIndex < 0 then 0 else if endIndex > slen then slen else endIndex
  in
  let a, b = if s0 > e0 then (e0, s0) else (s0, e0) in
  if a >= slen || b <= a then
    ""
  else
    String.sub s a (b - a)

let toString (s : string) () : string =
  s

let fromCharCode (code : int) : string =
  if code < 0 || code > 255 then
    ""
  else
    String.make 1 (Char.chr code)

(* URL encoding/decoding used by Haxe Serializer/Unserializer.

   Semantics target
   - `urlEncode`: encode bytes using `%HH` and keep RFC3986 unreserved bytes.
   - `urlDecode`: mirror Haxe std behavior by treating `+` as space first, then
     decoding `%HH` sequences.

   This is intentionally byte-based (OCaml strings), which is compatible with
   Haxe String UTF-8 storage model used by serializer payloads. *)

let is_unreserved (code : int) : bool =
  (code >= 0x41 && code <= 0x5A) (* A-Z *)
  || (code >= 0x61 && code <= 0x7A) (* a-z *)
  || (code >= 0x30 && code <= 0x39) (* 0-9 *)
  || code = 0x2D (* - *)
  || code = 0x5F (* _ *)
  || code = 0x2E (* . *)
  || code = 0x7E (* ~ *)

let hex_upper (n : int) : char =
  if n < 10 then
    Char.chr (Char.code '0' + n)
  else
    Char.chr (Char.code 'A' + (n - 10))

let urlEncode (s : string) : string =
  let len = String.length s in
  let b = Buffer.create (len * 3) in
  for i = 0 to len - 1 do
    let code = Char.code s.[i] in
    if is_unreserved code then
      Buffer.add_char b s.[i]
    else (
      Buffer.add_char b '%';
      Buffer.add_char b (hex_upper ((code lsr 4) land 0xF));
      Buffer.add_char b (hex_upper (code land 0xF))
    )
  done;
  Buffer.contents b

let hex_value (c : char) : int =
  let code = Char.code c in
  if code >= Char.code '0' && code <= Char.code '9' then
    code - Char.code '0'
  else if code >= Char.code 'A' && code <= Char.code 'F' then
    10 + (code - Char.code 'A')
  else if code >= Char.code 'a' && code <= Char.code 'f' then
    10 + (code - Char.code 'a')
  else
    -1

let urlDecode (s : string) : string =
  let len = String.length s in
  let b = Buffer.create len in
  let rec loop i =
    if i >= len then
      ()
    else
      match s.[i] with
      | '+' ->
          Buffer.add_char b ' ';
          loop (i + 1)
      | '%' when i + 2 < len ->
          let hi = hex_value s.[i + 1] in
          let lo = hex_value s.[i + 2] in
          if hi >= 0 && lo >= 0 then (
            Buffer.add_char b (Char.chr ((hi lsl 4) lor lo));
            loop (i + 3)
          ) else (
            Buffer.add_char b '%';
            loop (i + 1)
          )
      | c ->
          Buffer.add_char b c;
          loop (i + 1)
  in
  loop 0;
  Buffer.contents b
