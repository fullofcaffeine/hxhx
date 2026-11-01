(* Haxe String runtime for reflaxe.ocaml.

   A Haxe String is an OCaml `string` holding UTF-8 bytes. The String API
   counts Unicode code points, as upstream Haxe 4.3.7 eval does: in
   "h\xc3\xa9" (two code points, three bytes) `length` is 2 and
   `charCodeAt 1` is 233. Every index, length, and character code below is a
   code-point value; byte offsets stay private to this module.

   Bytes that do not start a well-formed UTF-8 sequence count as one character
   whose code is the byte value. Eval cannot create such a String, but OCaml
   file and process input can, and this keeps every operation total.

   Speed: a string's ASCII flag, code-point count, and sparse
   code-point-to-byte marks are computed in one pass. Strings shorter than
   [cache_min_bytes] are scanned directly. Longer strings are remembered in a
   small cache keyed by physical identity, so a lexer that reads one source
   string many times scans it once. An ASCII string then indexes bytes
   directly. *)

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
    Stdlib.String.equal a b

(* ---- UTF-8 decoding ---------------------------------------------------- *)

let byte_at (s : string) (i : int) : int =
  Stdlib.Char.code (Stdlib.String.unsafe_get s i)

let is_continuation (s : string) (len : int) (i : int) : bool =
  i < len && byte_at s i land 0xC0 = 0x80

(* Width of the well-formed UTF-8 sequence that starts at byte [i] (1-4), or 0
   when byte [i] does not start one. Overlong forms and values above U+10FFFF
   are not well formed. Encoded surrogates are accepted because
   `String.fromCharCode` produces them, as upstream eval does. *)
let sequence_width (s : string) (len : int) (i : int) : int =
  let b0 = byte_at s i in
  if b0 < 0x80 then 1
  else if b0 < 0xC2 then 0
  else if b0 < 0xE0 then (if is_continuation s len (i + 1) then 2 else 0)
  else if b0 < 0xF0 then (
    if i + 2 >= len then 0
    else
      let b1 = byte_at s (i + 1) in
      if b0 = 0xE0 && b1 < 0xA0 then 0
      else if b1 land 0xC0 = 0x80 && is_continuation s len (i + 2) then 3
      else 0)
  else if b0 < 0xF5 then (
    if i + 3 >= len then 0
    else
      let b1 = byte_at s (i + 1) in
      if (b0 = 0xF0 && b1 < 0x90) || (b0 = 0xF4 && b1 > 0x8F) then 0
      else if b1 land 0xC0 = 0x80 && is_continuation s len (i + 2) && is_continuation s len (i + 3) then 4
      else 0)
  else 0

(* Bytes taken by the character at byte [i]; an ill-formed byte is one character. *)
let character_width (s : string) (len : int) (i : int) : int =
  let width = sequence_width s len i in
  if width = 0 then 1 else width

(* Character code at byte [i]; an ill-formed byte yields its own value. *)
let code_at (s : string) (len : int) (i : int) : int =
  let b0 = byte_at s i in
  match sequence_width s len i with
  | 2 -> ((b0 land 0x1F) lsl 6) lor (byte_at s (i + 1) land 0x3F)
  | 3 -> ((b0 land 0x0F) lsl 12) lor ((byte_at s (i + 1) land 0x3F) lsl 6) lor (byte_at s (i + 2) land 0x3F)
  | 4 ->
      ((b0 land 0x07) lsl 18)
      lor ((byte_at s (i + 1) land 0x3F) lsl 12)
      lor ((byte_at s (i + 2) land 0x3F) lsl 6)
      lor (byte_at s (i + 3) land 0x3F)
  | _ -> b0

(* Appends code point [code] as UTF-8. Callers pass 0..0x10FFFF. *)
let add_code (b : Stdlib.Buffer.t) (code : int) : unit =
  if code < 0x80 then Stdlib.Buffer.add_char b (Stdlib.Char.unsafe_chr code)
  else if code < 0x800 then (
    Stdlib.Buffer.add_char b (Stdlib.Char.unsafe_chr (0xC0 lor (code lsr 6)));
    Stdlib.Buffer.add_char b (Stdlib.Char.unsafe_chr (0x80 lor (code land 0x3F))))
  else if code < 0x10000 then (
    Stdlib.Buffer.add_char b (Stdlib.Char.unsafe_chr (0xE0 lor (code lsr 12)));
    Stdlib.Buffer.add_char b (Stdlib.Char.unsafe_chr (0x80 lor ((code lsr 6) land 0x3F)));
    Stdlib.Buffer.add_char b (Stdlib.Char.unsafe_chr (0x80 lor (code land 0x3F))))
  else (
    Stdlib.Buffer.add_char b (Stdlib.Char.unsafe_chr (0xF0 lor (code lsr 18)));
    Stdlib.Buffer.add_char b (Stdlib.Char.unsafe_chr (0x80 lor ((code lsr 12) land 0x3F)));
    Stdlib.Buffer.add_char b (Stdlib.Char.unsafe_chr (0x80 lor ((code lsr 6) land 0x3F)));
    Stdlib.Buffer.add_char b (Stdlib.Char.unsafe_chr (0x80 lor (code land 0x3F))))

(* Index of the first byte >= 0x80 at or after [from], or [len]. *)
let first_non_ascii (s : string) (from : int) (len : int) : int =
  let i = ref from in
  while !i < len && byte_at s !i < 0x80 do
    incr i
  done;
  !i

(* ---- Code-point layout ------------------------------------------------- *)

let mark_bits = 5
let mark_stride = 1 lsl mark_bits

(* What one pass over a string learns about it.
   - [count] is the number of code points.
   - When [ascii] holds, code point i is byte i and [marks] is empty.
   - Otherwise [marks.(k)] is the byte offset of code point [k * mark_stride].
   - [cursor] packs the last resolved (code point, byte) pair into one word
     ([index lsl cursor_bits lor byte]), or is -1. A single word cannot tear,
     so a race between threads at worst loses the hint.
   - [hits] ranks cache entries. Every other field is immutable. *)
type layout = {
  text : string;
  bytes : int;
  count : int;
  ascii : bool;
  marks : int array;
  mutable cursor : int;
  mutable hits : int;
}

let cursor_bits = 31
let cursor_mask = (1 lsl cursor_bits) - 1
let cursor_enabled (bytes : int) : bool = Stdlib.Sys.int_size >= 63 && bytes <= cursor_mask

let scan (s : string) : layout =
  let n = Stdlib.String.length s in
  let first = first_non_ascii s 0 n in
  if first = n then
    { text = s; bytes = n; count = n; ascii = true; marks = [||]; cursor = -1; hits = 0 }
  else (
    let marks = Stdlib.Array.make ((n lsr mark_bits) + 1) 0 in
    let k = ref 0 in
    while !k lsl mark_bits < first do
      Stdlib.Array.set marks !k (!k lsl mark_bits);
      incr k
    done;
    let index = ref first in
    let byte = ref first in
    while !byte < n do
      if !index land (mark_stride - 1) = 0 then Stdlib.Array.set marks (!index lsr mark_bits) (!byte);
      byte := !byte + character_width s n !byte;
      incr index
    done;
    { text = s; bytes = n; count = !index; ascii = false; marks; cursor = -1; hits = 0 })

let remember_cursor (l : layout) (index : int) (byte : int) : unit =
  if cursor_enabled l.bytes then l.cursor <- (index lsl cursor_bits) lor byte

(* Byte offset of code point [i], for 0 <= i <= count. *)
let byte_offset (l : layout) (i : int) : int =
  if l.ascii then i
  else if i >= l.count then l.bytes
  else (
    let k = i lsr mark_bits in
    let index = ref (k lsl mark_bits) in
    let byte = ref (Stdlib.Array.get l.marks k) in
    let c = l.cursor in
    if c >= 0 then (
      let ci = c lsr cursor_bits in
      if ci <= i && ci > !index then (
        index := ci;
        byte := c land cursor_mask));
    while !index < i do
      byte := !byte + character_width l.text l.bytes !byte;
      incr index
    done;
    remember_cursor l i !byte;
    !byte)

(* Code-point index of the character that starts at byte [b], or -1 when [b]
   falls inside a character. [b = bytes] yields [count]. *)
let index_of_byte (l : layout) (b : int) : int =
  if l.ascii then b
  else if b >= l.bytes then l.count
  else (
    (* Last mark at or before [b]. *)
    let lo = ref 0 in
    let hi = ref ((l.count - 1) lsr mark_bits) in
    while !lo < !hi do
      let mid = (!lo + !hi + 1) lsr 1 in
      if (Stdlib.Array.get l.marks mid) <= b then lo := mid else hi := mid - 1
    done;
    let index = ref (!lo lsl mark_bits) in
    let byte = ref (Stdlib.Array.get l.marks !lo) in
    let c = l.cursor in
    if c >= 0 then (
      let cb = c land cursor_mask in
      if cb <= b && cb > !byte then (
        index := c lsr cursor_bits;
        byte := cb));
    while !byte < b do
      byte := !byte + character_width l.text l.bytes !byte;
      incr index
    done;
    if !byte = b then (
      remember_cursor l !index b;
      !index)
    else -1)

(* ---- Layout cache -------------------------------------------------------

   Shorter strings are cheaper to rescan than to cache. A new long string
   enters a probation ring; a second hit there promotes it into the protected
   set, replacing the protected entry with the fewest hits. Promotion halves
   every protected hit count, so old favorites age out. A stream of strings
   that are used once therefore never evicts a source string that a lexer
   reads constantly. *)

let cache_min_bytes = 64
let cache_ways = 4
let empty_layout : layout = scan (Stdlib.Bytes.to_string (Stdlib.Bytes.make cache_min_bytes ' '))
let protected_layouts : layout array = Stdlib.Array.make cache_ways empty_layout
let probation_layouts : layout array = Stdlib.Array.make cache_ways empty_layout
let probation_next = ref 0

let promote (slot : int) (l : layout) : unit =
  let victim = ref 0 in
  for j = 1 to cache_ways - 1 do
    if (Stdlib.Array.get protected_layouts j).hits < (Stdlib.Array.get protected_layouts !victim).hits then victim := j
  done;
  let evicted = (Stdlib.Array.get protected_layouts !victim) in
  for j = 0 to cache_ways - 1 do
    let e = (Stdlib.Array.get protected_layouts j) in
    e.hits <- e.hits lsr 1
  done;
  Stdlib.Array.set protected_layouts !victim l;
  Stdlib.Array.set probation_layouts slot evicted

(* Each finder returns [empty_layout] on a miss, so a hit does not allocate. *)
let rec find_protected (s : string) (j : int) : layout =
  if j >= cache_ways then empty_layout
  else
    let l = (Stdlib.Array.get protected_layouts j) in
    if l.text == s then (
      if l.hits < max_int then l.hits <- l.hits + 1;
      l)
    else find_protected s (j + 1)

let rec find_probation (s : string) (j : int) : layout =
  if j >= cache_ways then empty_layout
  else
    let l = (Stdlib.Array.get probation_layouts j) in
    if l.text == s then (
      l.hits <- l.hits + 1;
      if l.hits >= 2 then promote j l;
      l)
    else find_probation s (j + 1)

let layout (s : string) : layout =
  if Stdlib.String.length s < cache_min_bytes then scan s
  else
    let l = find_protected s 0 in
    if l != empty_layout then l
    else
      let l = find_probation s 0 in
      if l != empty_layout then l
      else (
        let l = scan s in
        let slot = !probation_next in
        Stdlib.Array.set probation_layouts slot l;
        probation_next := (slot + 1) mod cache_ways;
        l)

(* Code-point count of a short string without allocating a layout. *)
let count_direct (s : string) (n : int) : int =
  let count = ref 0 in
  let i = ref 0 in
  while !i < n do
    i := !i + character_width s n !i;
    incr count
  done;
  !count

(* Byte offset of code point [index] in a short string, or -1 past the end. *)
let byte_offset_direct (s : string) (n : int) (index : int) : int =
  let i = ref 0 in
  let k = ref 0 in
  while !k < index && !i < n do
    i := !i + character_width s n !i;
    incr k
  done;
  if !i < n then !i else -1

(* ---- String API ---------------------------------------------------------- *)

let length (s : string) : int =
  let n = Stdlib.String.length s in
  if n < cache_min_bytes then count_direct s n else (layout s).count

(* Byte offset of code point [index] when it names a character, or -1. *)
let character_offset (s : string) (index : int) : int =
  let n = Stdlib.String.length s in
  if index < 0 then -1
  else if n < cache_min_bytes then byte_offset_direct s n index
  else
    let l = layout s in
    if index >= l.count then -1 else byte_offset l index

(* BEGIN generated case tables: scripts/reflaxe-ocaml/generate-hxstring-case-table.js *)
(* 2224 code points change case; 170 upper and 162 lower runs. *)
let upper_runs : int array = [|
  0x61; 0x7a; 1; -32; 0xb5; 0xb5; 1; 743; 0xe0; 0xf6; 1; -32; 0xf8; 0xfe; 1; -32;
  0xff; 0xff; 1; 121; 0x101; 0x12f; 2; -1; 0x131; 0x131; 1; -232; 0x133; 0x137; 2; -1;
  0x13a; 0x148; 2; -1; 0x14b; 0x177; 2; -1; 0x17a; 0x17e; 2; -1; 0x17f; 0x17f; 1; -300;
  0x180; 0x180; 1; 195; 0x183; 0x185; 2; -1; 0x188; 0x188; 1; -1; 0x18c; 0x18c; 1; -1;
  0x192; 0x192; 1; -1; 0x195; 0x195; 1; 97; 0x199; 0x199; 1; -1; 0x19a; 0x19a; 1; 163;
  0x19e; 0x19e; 1; 130; 0x1a1; 0x1a5; 2; -1; 0x1a8; 0x1a8; 1; -1; 0x1ad; 0x1ad; 1; -1;
  0x1b0; 0x1b0; 1; -1; 0x1b4; 0x1b6; 2; -1; 0x1b9; 0x1b9; 1; -1; 0x1bd; 0x1bd; 1; -1;
  0x1bf; 0x1bf; 1; 56; 0x1c4; 0x1c4; 1; 1; 0x1c6; 0x1c6; 1; -1; 0x1c7; 0x1c7; 1; 1;
  0x1c9; 0x1c9; 1; -1; 0x1ca; 0x1ca; 1; 1; 0x1cc; 0x1dc; 2; -1; 0x1dd; 0x1dd; 1; -79;
  0x1df; 0x1ef; 2; -1; 0x1f1; 0x1f1; 1; 1; 0x1f3; 0x1f5; 2; -1; 0x1f9; 0x21f; 2; -1;
  0x223; 0x233; 2; -1; 0x23c; 0x23c; 1; -1; 0x23f; 0x240; 1; 10815; 0x242; 0x242; 1; -1;
  0x247; 0x24f; 2; -1; 0x250; 0x250; 1; 10783; 0x251; 0x251; 1; 10780; 0x252; 0x252; 1; 10782;
  0x253; 0x253; 1; -210; 0x254; 0x254; 1; -206; 0x256; 0x257; 1; -205; 0x259; 0x259; 1; -202;
  0x25b; 0x25b; 1; -203; 0x25c; 0x25c; 1; 42319; 0x260; 0x260; 1; -205; 0x261; 0x261; 1; 42315;
  0x263; 0x263; 1; -207; 0x265; 0x265; 1; 42280; 0x266; 0x266; 1; 42308; 0x268; 0x268; 1; -209;
  0x269; 0x269; 1; -211; 0x26b; 0x26b; 1; 10743; 0x26c; 0x26c; 1; 42305; 0x26f; 0x26f; 1; -211;
  0x271; 0x271; 1; 10749; 0x272; 0x272; 1; -213; 0x275; 0x275; 1; -214; 0x27d; 0x27d; 1; 10727;
  0x280; 0x280; 1; -218; 0x283; 0x283; 1; -218; 0x287; 0x287; 1; 42282; 0x288; 0x288; 1; -218;
  0x289; 0x289; 1; -69; 0x28a; 0x28b; 1; -217; 0x28c; 0x28c; 1; -71; 0x292; 0x292; 1; -219;
  0x29d; 0x29d; 1; 42261; 0x29e; 0x29e; 1; 42258; 0x345; 0x345; 1; 84; 0x371; 0x373; 2; -1;
  0x377; 0x377; 1; -1; 0x37b; 0x37d; 1; 130; 0x3ac; 0x3ac; 1; -38; 0x3ad; 0x3af; 1; -37;
  0x3b1; 0x3c1; 1; -32; 0x3c2; 0x3c2; 1; -31; 0x3c3; 0x3cb; 1; -32; 0x3cc; 0x3cc; 1; -64;
  0x3cd; 0x3ce; 1; -63; 0x3d0; 0x3d0; 1; -62; 0x3d1; 0x3d1; 1; -57; 0x3d5; 0x3d5; 1; -47;
  0x3d6; 0x3d6; 1; -54; 0x3d7; 0x3d7; 1; -8; 0x3d9; 0x3ef; 2; -1; 0x3f0; 0x3f0; 1; -86;
  0x3f1; 0x3f1; 1; -80; 0x3f2; 0x3f2; 1; 7; 0x3f3; 0x3f3; 1; -116; 0x3f5; 0x3f5; 1; -96;
  0x3f8; 0x3f8; 1; -1; 0x3fb; 0x3fb; 1; -1; 0x430; 0x44f; 1; -32; 0x450; 0x45f; 1; -80;
  0x461; 0x481; 2; -1; 0x48b; 0x4bf; 2; -1; 0x4c2; 0x4ce; 2; -1; 0x4cf; 0x4cf; 1; -15;
  0x4d1; 0x52f; 2; -1; 0x561; 0x586; 1; -48; 0x13f8; 0x13fd; 1; -8; 0x1d79; 0x1d79; 1; 35332;
  0x1d7d; 0x1d7d; 1; 3814; 0x1e01; 0x1e95; 2; -1; 0x1e9b; 0x1e9b; 1; -59; 0x1ea1; 0x1eff; 2; -1;
  0x1f00; 0x1f07; 1; 8; 0x1f10; 0x1f15; 1; 8; 0x1f20; 0x1f27; 1; 8; 0x1f30; 0x1f37; 1; 8;
  0x1f40; 0x1f45; 1; 8; 0x1f51; 0x1f57; 2; 8; 0x1f60; 0x1f67; 1; 8; 0x1f70; 0x1f71; 1; 74;
  0x1f72; 0x1f75; 1; 86; 0x1f76; 0x1f77; 1; 100; 0x1f78; 0x1f79; 1; 128; 0x1f7a; 0x1f7b; 1; 112;
  0x1f7c; 0x1f7d; 1; 126; 0x1f80; 0x1f87; 1; 8; 0x1f90; 0x1f97; 1; 8; 0x1fa0; 0x1fa7; 1; 8;
  0x1fb0; 0x1fb1; 1; 8; 0x1fb3; 0x1fb3; 1; 9; 0x1fbe; 0x1fbe; 1; -7205; 0x1fc3; 0x1fc3; 1; 9;
  0x1fd0; 0x1fd1; 1; 8; 0x1fe0; 0x1fe1; 1; 8; 0x1fe5; 0x1fe5; 1; 7; 0x1ff3; 0x1ff3; 1; 9;
  0x214e; 0x214e; 1; -28; 0x2170; 0x217f; 1; -16; 0x2184; 0x2184; 1; -1; 0x24d0; 0x24e9; 1; -26;
  0x2c30; 0x2c5e; 1; -48; 0x2c61; 0x2c61; 1; -1; 0x2c65; 0x2c65; 1; -10795; 0x2c66; 0x2c66; 1; -10792;
  0x2c68; 0x2c6c; 2; -1; 0x2c73; 0x2c73; 1; -1; 0x2c76; 0x2c76; 1; -1; 0x2c81; 0x2ce3; 2; -1;
  0x2cec; 0x2cee; 2; -1; 0x2cf3; 0x2cf3; 1; -1; 0x2d00; 0x2d25; 1; -7264; 0x2d27; 0x2d27; 1; -7264;
  0x2d2d; 0x2d2d; 1; -7264; 0xa641; 0xa66d; 2; -1; 0xa681; 0xa69b; 2; -1; 0xa723; 0xa72f; 2; -1;
  0xa733; 0xa76f; 2; -1; 0xa77a; 0xa77c; 2; -1; 0xa77f; 0xa787; 2; -1; 0xa78c; 0xa78c; 1; -1;
  0xa791; 0xa793; 2; -1; 0xa797; 0xa7a9; 2; -1; 0xa7b5; 0xa7b7; 2; -1; 0xab53; 0xab53; 1; -928;
  0xab70; 0xabbf; 1; -38864; 0xff41; 0xff5a; 1; -32;
|]

let lower_runs : int array = [|
  0x41; 0x5a; 1; 32; 0xc0; 0xd6; 1; 32; 0xd8; 0xde; 1; 32; 0x100; 0x12e; 2; 1;
  0x130; 0x130; 1; -199; 0x132; 0x136; 2; 1; 0x139; 0x147; 2; 1; 0x14a; 0x176; 2; 1;
  0x178; 0x178; 1; -121; 0x179; 0x17d; 2; 1; 0x181; 0x181; 1; 210; 0x182; 0x184; 2; 1;
  0x186; 0x186; 1; 206; 0x187; 0x187; 1; 1; 0x189; 0x18a; 1; 205; 0x18b; 0x18b; 1; 1;
  0x18e; 0x18e; 1; 79; 0x18f; 0x18f; 1; 202; 0x190; 0x190; 1; 203; 0x191; 0x191; 1; 1;
  0x193; 0x193; 1; 205; 0x194; 0x194; 1; 207; 0x196; 0x196; 1; 211; 0x197; 0x197; 1; 209;
  0x198; 0x198; 1; 1; 0x19c; 0x19c; 1; 211; 0x19d; 0x19d; 1; 213; 0x19f; 0x19f; 1; 214;
  0x1a0; 0x1a4; 2; 1; 0x1a6; 0x1a6; 1; 218; 0x1a7; 0x1a7; 1; 1; 0x1a9; 0x1a9; 1; 218;
  0x1ac; 0x1ac; 1; 1; 0x1ae; 0x1ae; 1; 218; 0x1af; 0x1af; 1; 1; 0x1b1; 0x1b2; 1; 217;
  0x1b3; 0x1b5; 2; 1; 0x1b7; 0x1b7; 1; 219; 0x1b8; 0x1b8; 1; 1; 0x1bc; 0x1bc; 1; 1;
  0x1c4; 0x1c4; 1; 2; 0x1c5; 0x1c5; 1; 1; 0x1c7; 0x1c7; 1; 2; 0x1c8; 0x1c8; 1; 1;
  0x1ca; 0x1ca; 1; 2; 0x1cb; 0x1db; 2; 1; 0x1de; 0x1ee; 2; 1; 0x1f1; 0x1f1; 1; 2;
  0x1f2; 0x1f4; 2; 1; 0x1f6; 0x1f6; 1; -97; 0x1f7; 0x1f7; 1; -56; 0x1f8; 0x21e; 2; 1;
  0x220; 0x220; 1; -130; 0x222; 0x232; 2; 1; 0x23a; 0x23a; 1; 10795; 0x23b; 0x23b; 1; 1;
  0x23d; 0x23d; 1; -163; 0x23e; 0x23e; 1; 10792; 0x241; 0x241; 1; 1; 0x243; 0x243; 1; -195;
  0x244; 0x244; 1; 69; 0x245; 0x245; 1; 71; 0x246; 0x24e; 2; 1; 0x370; 0x372; 2; 1;
  0x376; 0x376; 1; 1; 0x37f; 0x37f; 1; 116; 0x386; 0x386; 1; 38; 0x388; 0x38a; 1; 37;
  0x38c; 0x38c; 1; 64; 0x38e; 0x38f; 1; 63; 0x391; 0x3a1; 1; 32; 0x3a3; 0x3ab; 1; 32;
  0x3cf; 0x3cf; 1; 8; 0x3d8; 0x3ee; 2; 1; 0x3f4; 0x3f4; 1; -60; 0x3f7; 0x3f7; 1; 1;
  0x3f9; 0x3f9; 1; -7; 0x3fa; 0x3fa; 1; 1; 0x3fd; 0x3ff; 1; -130; 0x400; 0x40f; 1; 80;
  0x410; 0x42f; 1; 32; 0x460; 0x480; 2; 1; 0x48a; 0x4be; 2; 1; 0x4c0; 0x4c0; 1; 15;
  0x4c1; 0x4cd; 2; 1; 0x4d0; 0x52e; 2; 1; 0x531; 0x556; 1; 48; 0x10a0; 0x10c5; 1; 7264;
  0x10c7; 0x10c7; 1; 7264; 0x10cd; 0x10cd; 1; 7264; 0x13a0; 0x13ef; 1; 38864; 0x13f0; 0x13f5; 1; 8;
  0x1e00; 0x1e94; 2; 1; 0x1e9e; 0x1e9e; 1; -7615; 0x1ea0; 0x1efe; 2; 1; 0x1f08; 0x1f0f; 1; -8;
  0x1f18; 0x1f1d; 1; -8; 0x1f28; 0x1f2f; 1; -8; 0x1f38; 0x1f3f; 1; -8; 0x1f48; 0x1f4d; 1; -8;
  0x1f59; 0x1f5f; 2; -8; 0x1f68; 0x1f6f; 1; -8; 0x1f88; 0x1f8f; 1; -8; 0x1f98; 0x1f9f; 1; -8;
  0x1fa8; 0x1faf; 1; -8; 0x1fb8; 0x1fb9; 1; -8; 0x1fba; 0x1fbb; 1; -74; 0x1fbc; 0x1fbc; 1; -9;
  0x1fc8; 0x1fcb; 1; -86; 0x1fcc; 0x1fcc; 1; -9; 0x1fd8; 0x1fd9; 1; -8; 0x1fda; 0x1fdb; 1; -100;
  0x1fe8; 0x1fe9; 1; -8; 0x1fea; 0x1feb; 1; -112; 0x1fec; 0x1fec; 1; -7; 0x1ff8; 0x1ff9; 1; -128;
  0x1ffa; 0x1ffb; 1; -126; 0x1ffc; 0x1ffc; 1; -9; 0x2126; 0x2126; 1; -7517; 0x212a; 0x212a; 1; -8383;
  0x212b; 0x212b; 1; -8262; 0x2132; 0x2132; 1; 28; 0x2160; 0x216f; 1; 16; 0x2183; 0x2183; 1; 1;
  0x24b6; 0x24cf; 1; 26; 0x2c00; 0x2c2e; 1; 48; 0x2c60; 0x2c60; 1; 1; 0x2c62; 0x2c62; 1; -10743;
  0x2c63; 0x2c63; 1; -3814; 0x2c64; 0x2c64; 1; -10727; 0x2c67; 0x2c6b; 2; 1; 0x2c6d; 0x2c6d; 1; -10780;
  0x2c6e; 0x2c6e; 1; -10749; 0x2c6f; 0x2c6f; 1; -10783; 0x2c70; 0x2c70; 1; -10782; 0x2c72; 0x2c72; 1; 1;
  0x2c75; 0x2c75; 1; 1; 0x2c7e; 0x2c7f; 1; -10815; 0x2c80; 0x2ce2; 2; 1; 0x2ceb; 0x2ced; 2; 1;
  0x2cf2; 0x2cf2; 1; 1; 0xa640; 0xa66c; 2; 1; 0xa680; 0xa69a; 2; 1; 0xa722; 0xa72e; 2; 1;
  0xa732; 0xa76e; 2; 1; 0xa779; 0xa77b; 2; 1; 0xa77d; 0xa77d; 1; -35332; 0xa77e; 0xa786; 2; 1;
  0xa78b; 0xa78b; 1; 1; 0xa78d; 0xa78d; 1; -42280; 0xa790; 0xa792; 2; 1; 0xa796; 0xa7a8; 2; 1;
  0xa7aa; 0xa7aa; 1; -42308; 0xa7ab; 0xa7ab; 1; -42319; 0xa7ac; 0xa7ac; 1; -42315; 0xa7ad; 0xa7ad; 1; -42305;
  0xa7b0; 0xa7b0; 1; -42258; 0xa7b1; 0xa7b1; 1; -42282; 0xa7b2; 0xa7b2; 1; -42261; 0xa7b3; 0xa7b3; 1; 928;
  0xa7b4; 0xa7b6; 2; 1; 0xff21; 0xff3a; 1; 32;
|]
(* END generated case tables *)

(* Maps [code] through a run table; codes outside every run map to themselves. *)
let map_case (runs : int array) (code : int) : int =
  let rows = Stdlib.Array.length runs / 4 in
  let lo = ref 0 in
  let hi = ref (rows - 1) in
  while !lo < !hi do
    let mid = (!lo + !hi + 1) lsr 1 in
    if (Stdlib.Array.get runs (mid * 4)) <= code then lo := mid else hi := mid - 1
  done;
  let row = !lo * 4 in
  let first = (Stdlib.Array.get runs row) in
  if code >= first && code <= (Stdlib.Array.get runs (row + 1)) && (code - first) mod (Stdlib.Array.get runs (row + 2)) = 0 then code + (Stdlib.Array.get runs (row + 3))
  else code

(* Case conversion is one code point to one code point (simple case mapping),
   as in upstream eval: "\xc3\x9f" (sharp s) stays unchanged. Ill-formed bytes
   are copied unchanged. *)
let convert_case (runs : int array) (ascii : string -> string) (s : string) : string =
  let n = Stdlib.String.length s in
  if first_non_ascii s 0 n = n then ascii s
  else (
    let b = Stdlib.Buffer.create n in
    let i = ref 0 in
    while !i < n do
      let width = sequence_width s n !i in
      if width = 0 then (
        Stdlib.Buffer.add_char b (Stdlib.String.unsafe_get s !i);
        incr i)
      else (
        add_code b (map_case runs (code_at s n !i));
        i := !i + width)
    done;
    Stdlib.Buffer.contents b)

let toUpperCase (s : string) () : string =
  convert_case upper_runs Stdlib.String.uppercase_ascii s

let toLowerCase (s : string) () : string =
  convert_case lower_runs Stdlib.String.lowercase_ascii s

let charAt (s : string) (index : int) : string =
  let b = character_offset s index in
  if b < 0 then ""
  else
    let n = Stdlib.String.length s in
    Stdlib.String.sub s b (character_width s n b)

(* Haxe: String.charCodeAt returns Null<Int> and yields null on OOB. *)
let charCodeAt (s : string) (index : int) : Obj.t =
  let b = character_offset s index in
  if b < 0 then HxRuntime.hx_null else Obj.repr (code_at s (Stdlib.String.length s) b)

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
    let b = character_offset s index in
    if b < 0 then -1 else code_at s (Stdlib.String.length s) b

let starts_with_at (s : string) (sub : string) (i : int) : bool =
  let slen = Stdlib.String.length s in
  let nlen = Stdlib.String.length sub in
  if i < 0 || i + nlen > slen then
    false
  else
    let rec loop j =
      if j >= nlen then
        true
      else if (Stdlib.String.get s (i + j)) = (Stdlib.String.get sub (j)) then
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

(* Whether [sub] occurs at byte [i] and both ends of the match fall on
   character boundaries. A well-formed needle that starts on a boundary also
   ends on one; the check matters only for ill-formed text, where "\xC3" must
   not match inside "\xC3\xA9". *)
let on_boundaries (l : layout) (sub : string) (i : int) : bool =
  starts_with_at l.text sub i
  && index_of_byte l i >= 0
  && index_of_byte l (i + Stdlib.String.length sub) >= 0

(* First byte offset >= [from] where [sub] matches on character boundaries, or -1. *)
let find_forward (l : layout) (sub : string) (from : int) : int =
  let limit = l.bytes - Stdlib.String.length sub in
  let rec search i =
    if i > limit then -1
    else if on_boundaries l sub i then i
    else search (i + 1)
  in
  search from

let find_backward (l : layout) (sub : string) (from : int) : int =
  let rec search i =
    if i < 0 then -1
    else if on_boundaries l sub i then i
    else search (i - 1)
  in
  search from

let indexOf (s : string) (sub : string) (startIndex : int) : int =
  let l = layout s in
  let slen = l.count in
  let nlen = length sub in
  let startIndex = unwrap_optional_int startIndex 0 in
  if startIndex > slen then
    -1
  else if nlen = 0 then
    if startIndex < 0 then 0 else startIndex
  else (
    let start = if startIndex < 0 then 0 else startIndex in
    let found = find_forward l sub (byte_offset l start) in
    if found < 0 then -1 else index_of_byte l found
  )

let lastIndexOf (s : string) (sub : string) (startIndex : int) : int =
  let l = layout s in
  let slen = l.count in
  let nlen = length sub in
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
        if clamped > max_pos then max_pos else clamped
      in
      let found = find_backward l sub (byte_offset l start) in
      if found < 0 then -1 else index_of_byte l found
    )
  )

let split (s : string) (delimiter : string) : string HxArray.t =
  let out = HxArray.create () in
  let slen = Stdlib.String.length s in
  let dlen = Stdlib.String.length delimiter in
  if dlen = 0 then (
    let i = ref 0 in
    while !i < slen do
      let width = character_width s slen !i in
      ignore (HxArray.push out (Stdlib.String.sub s !i width));
      i := !i + width
    done;
    out
  ) else (
    let l = layout s in
    let rec loop start =
      let idx = find_forward l delimiter start in
      if idx < 0 then (
        ignore (HxArray.push out (Stdlib.String.sub s start (slen - start)));
        out
      ) else (
        ignore (HxArray.push out (Stdlib.String.sub s start (idx - start)));
        loop (idx + dlen)
      )
    in
    loop 0
  )

(* Substring between code points [a] and [b], 0 <= a <= b <= count. *)
let slice (l : layout) (a : int) (b : int) : string =
  if b <= a then ""
  else
    let first = byte_offset l a in
    Stdlib.String.sub l.text first (byte_offset l b - first)

let substr (s : string) (pos : int) (len : int) : string =
  let l = layout s in
  let slen = l.count in
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
    let l0 = if len < 0 then slen - p else len in
    if l0 <= 0 then
      ""
    else
      let max_len = slen - p in
      let l2 = if l0 > max_len then max_len else l0 in
      slice l p (p + l2)

let substring (s : string) (startIndex : int) (endIndex : int) : string =
  let l = layout s in
  let slen = l.count in
  let endIndex = unwrap_optional_int endIndex slen in
  let s0 = if startIndex < 0 then 0 else startIndex in
  let e0 =
    if endIndex < 0 then 0 else if endIndex > slen then slen else endIndex
  in
  let a, b = if s0 > e0 then (e0, s0) else (s0, e0) in
  let b = if b > slen then slen else b in
  if a >= slen || b <= a then
    ""
  else
    slice l a b

let toString (s : string) () : string =
  s

(* UTF-8 for 0..0x10FFFF, surrogates included as upstream eval encodes them.
   Other values yield "". *)
let fromCharCode (code : int) : string =
  if code < 0 || code > 0x10FFFF then
    ""
  else if code < 0x80 then
    Stdlib.String.make 1 (Stdlib.Char.chr code)
  else (
    let b = Stdlib.Buffer.create 4 in
    add_code b code;
    Stdlib.Buffer.contents b)

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
    Stdlib.Char.chr (Stdlib.Char.code '0' + n)
  else
    Stdlib.Char.chr (Stdlib.Char.code 'A' + (n - 10))

let urlEncode (s : string) : string =
  let len = Stdlib.String.length s in
  let b = Stdlib.Buffer.create (len * 3) in
  for i = 0 to len - 1 do
    let code = Stdlib.Char.code (Stdlib.String.get s (i)) in
    if is_unreserved code then
      Stdlib.Buffer.add_char b (Stdlib.String.get s (i))
    else (
      Stdlib.Buffer.add_char b '%';
      Stdlib.Buffer.add_char b (hex_upper ((code lsr 4) land 0xF));
      Stdlib.Buffer.add_char b (hex_upper (code land 0xF))
    )
  done;
  Stdlib.Buffer.contents b

let hex_value (c : char) : int =
  let code = Stdlib.Char.code c in
  if code >= Stdlib.Char.code '0' && code <= Stdlib.Char.code '9' then
    code - Stdlib.Char.code '0'
  else if code >= Stdlib.Char.code 'A' && code <= Stdlib.Char.code 'F' then
    10 + (code - Stdlib.Char.code 'A')
  else if code >= Stdlib.Char.code 'a' && code <= Stdlib.Char.code 'f' then
    10 + (code - Stdlib.Char.code 'a')
  else
    -1

let urlDecode (s : string) : string =
  let len = Stdlib.String.length s in
  let b = Stdlib.Buffer.create len in
  let rec loop i =
    if i >= len then
      ()
    else
      match (Stdlib.String.get s (i)) with
      | '+' ->
          Stdlib.Buffer.add_char b ' ';
          loop (i + 1)
      | '%' when i + 2 < len ->
          let hi = hex_value (Stdlib.String.get s (i + 1)) in
          let lo = hex_value (Stdlib.String.get s (i + 2)) in
          if hi >= 0 && lo >= 0 then (
            Stdlib.Buffer.add_char b (Stdlib.Char.chr ((hi lsl 4) lor lo));
            loop (i + 3)
          ) else (
            Stdlib.Buffer.add_char b '%';
            loop (i + 1)
          )
      | c ->
          Stdlib.Buffer.add_char b c;
          loop (i + 1)
  in
  loop 0;
  Stdlib.Buffer.contents b
