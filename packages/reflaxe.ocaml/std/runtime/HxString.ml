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
  if isNull a then
    isNull b
  else if isNull b then
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

let indexOf (s : string) (sub : string) (startIndex : int) : int =
  let slen = String.length s in
  let nlen = String.length sub in
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
