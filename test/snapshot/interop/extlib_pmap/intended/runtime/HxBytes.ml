(* Haxe Bytes runtime for reflaxe.ocaml.

   Representation:
   - one record containing the explicit Haxe length and one mutable OCaml
     `bytes` value;
   - `getData` and `ofData` preserve the native data alias.

   Notes:
   - Haxe `Bytes` operations throw `haxe.io.Error.OutsideBounds` on most targets.
     For now we throw a simple string via `HxRuntime.hx_throw`.
   - This is byte-based and currently assumes Haxe `String` maps to OCaml `string`
     without additional encoding conversions. *)

type data = bytes

type t = {
  length : int;
  data : data;
}

let outside_bounds () : 'a =
  HxRuntime.hx_throw (Obj.repr "OutsideBounds")

let check_range (len_total : int) (pos : int) (len : int) : unit =
  if pos < 0 || len < 0 || pos + len > len_total then outside_bounds () else ()

let check_access (b : t) (pos : int) (len : int) : unit =
  check_range b.length pos len;
  check_range (Bytes.length b.data) pos len

let create (len : int) (data : data) : t =
  if len < 0 then outside_bounds () else { length = len; data }

let alloc (len : int) : t =
  if len < 0 then outside_bounds ()
  else create len (Bytes.make len '\000')

let length (b : t) : int =
  b.length

let get (b : t) (pos : int) : int =
  check_access b pos 1;
  Char.code (Bytes.get b.data pos)

let fastGet (data : data) (pos : int) : int =
  if pos < 0 || pos >= Bytes.length data then outside_bounds ()
  else Char.code (Bytes.get data pos)

let set (b : t) (pos : int) (v : int) : unit =
  check_access b pos 1;
  let c = Char.chr (v land 0xFF) in
  Bytes.set b.data pos c

let blit (dst : t) (pos : int) (src : t) (srcpos : int) (len : int) : unit =
  check_access dst pos len;
  check_access src srcpos len;
  if len = 0 then () else Bytes.blit src.data srcpos dst.data pos len

let fill (b : t) (pos : int) (len : int) (value : int) : unit =
  check_access b pos len;
  let c = Char.chr (value land 0xFF) in
  for i = 0 to len - 1 do
    Bytes.set b.data (pos + i) c
  done

let sub (b : t) (pos : int) (len : int) : t =
  check_access b pos len;
  create len (Bytes.sub b.data pos len)

let compare (a : t) (b : t) : int =
  let common = min a.length b.length in
  let rec loop i =
    if i >= common then Stdlib.compare a.length b.length
    else
      let difference = get a i - get b i in
      if difference = 0 then loop (i + 1) else difference
  in
  loop 0

let ofString (s : string) () : t =
  let data = Bytes.of_string s in
  create (Bytes.length data) data

let getString (b : t) (pos : int) (len : int) () : string =
  check_access b pos len;
  Bytes.sub_string b.data pos len

let toString (b : t) () : string =
  getString b 0 b.length ()

let getData (b : t) () : data =
  b.data

let ofData (data : data) () : t =
  create (Bytes.length data) data

let getUInt16 (b : t) (pos : int) : int =
  check_access b pos 2;
  get b pos lor (get b (pos + 1) lsl 8)

let setUInt16 (b : t) (pos : int) (v : int) : unit =
  check_access b pos 2;
  set b pos v;
  set b (pos + 1) (v lsr 8)

let getInt32 (b : t) (pos : int) : int =
  check_access b pos 4;
  let open Int32 in
  let byte i = of_int (get b (pos + i)) in
  let v =
    logor
      (logor (logor (byte 0) (shift_left (byte 1) 8)) (shift_left (byte 2) 16))
      (shift_left (byte 3) 24)
  in
  Int32.to_int v

let setInt32 (b : t) (pos : int) (v : int) : unit =
  check_access b pos 4;
  let open Int32 in
  let v32 = of_int v in
  let byte shift =
    to_int (logand (shift_right_logical v32 shift) 0xFFl)
  in
  set b pos (byte 0);
  set b (pos + 1) (byte 8);
  set b (pos + 2) (byte 16);
  set b (pos + 3) (byte 24)

(* Int64 stays a generated Haxe nominal record, so the reusable runtime cannot
   depend on Haxe_Int64 directly. The sealed syntax adapter supplies the exact
   constructor on reads and projects the exact low/high words once on writes.
   This module still owns range validation and little-endian word ordering. *)
let getInt64 (b : t) (pos : int) create =
  check_access b pos 8;
  let low = getInt32 b pos in
  let high = getInt32 b (pos + 4) in
  create high low

let setInt64 (b : t) (pos : int) (low : int) (high : int) : unit =
  check_access b pos 8;
  setInt32 b pos low;
  setInt32 b (pos + 4) high

let getFloat (b : t) (pos : int) : float =
  let bits = Int32.of_int (getInt32 b pos) in
  Int32.float_of_bits bits

let setFloat (b : t) (pos : int) (v : float) : unit =
  let bits = Int32.bits_of_float v in
  setInt32 b pos (Int32.to_int bits)

let getDouble (b : t) (pos : int) : float =
  check_access b pos 8;
  let open Int64 in
  let byte i = of_int (get b (pos + i)) in
  let v =
    logor
      (logor
         (logor
            (logor
               (logor
                  (logor
                     (logor (byte 0) (shift_left (byte 1) 8))
                     (shift_left (byte 2) 16))
                  (shift_left (byte 3) 24))
               (shift_left (byte 4) 32))
            (shift_left (byte 5) 40))
         (shift_left (byte 6) 48))
      (shift_left (byte 7) 56)
  in
  Int64.float_of_bits v

let setDouble (b : t) (pos : int) (v : float) : unit =
  check_access b pos 8;
  let open Int64 in
  let bits = bits_of_float v in
  let byte shift =
    to_int (logand (shift_right_logical bits shift) 0xFFL)
  in
  set b pos (byte 0);
  set b (pos + 1) (byte 8);
  set b (pos + 2) (byte 16);
  set b (pos + 3) (byte 24);
  set b (pos + 4) (byte 32);
  set b (pos + 5) (byte 40);
  set b (pos + 6) (byte 48);
  set b (pos + 7) (byte 56)

let toHex (b : t) () : string =
  let len = b.length in
  let out = Bytes.create (len * 2) in
  let hex = "0123456789abcdef" in
  for i = 0 to len - 1 do
    let v = get b i in
    Bytes.set out (i * 2) (Stdlib.String.get hex (v lsr 4));
    Bytes.set out (i * 2 + 1) (Stdlib.String.get hex (v land 15))
  done;
  Bytes.to_string out

let invalid_hex (msg : string) : 'a =
  HxRuntime.hx_throw (Obj.repr msg)

let hex_nibble (c : char) : int option =
  match c with
  | '0' .. '9' -> Some (Char.code c - Char.code '0')
  | 'a' .. 'f' -> Some (10 + Char.code c - Char.code 'a')
  | 'A' .. 'F' -> Some (10 + Char.code c - Char.code 'A')
  | _ -> None

let ofHex (s : string) : t =
  let len = Stdlib.String.length s in
  if len land 1 <> 0 then invalid_hex "Not a hex string (odd number of digits)"
  else
    let out = alloc (len lsr 1) in
    for i = 0 to (len lsr 1) - 1 do
      let hi = (Stdlib.String.get s (i * 2)) in
      let lo = (Stdlib.String.get s (i * 2 + 1)) in
      match (hex_nibble hi, hex_nibble lo) with
      | Some h, Some l -> set out i (((h lsl 4) lor l) land 0xFF)
      | _ -> invalid_hex "Not a hex string"
    done;
    out
