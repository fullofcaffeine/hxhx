(* OCaml runtime helpers for `haxe.io.FPHelper`.

   This module is intentionally small and uses OCaml's standard library primitives
   to perform IEEE754 "bit-casts" between floats and integers.

   See `std/_std/haxe/io/FPHelper.hx` for the rationale and the public Haxe API. *)

let floatToI32 (f : float) : int =
  Int32.to_int (Int32.bits_of_float f)

let i32ToFloat (i : int) : float =
  Int32.float_of_bits (Int32.of_int i)

let doubleToI64Parts (v : float) : int HxArray.t =
  let bits = Int64.bits_of_float v in
  let low_u = Int64.logand bits 0xFFFFFFFFL in
  let high_u = Int64.shift_right_logical bits 32 in
  let low = Int64.to_int low_u in
  let high = Int64.to_int high_u in
  let low_signed = if (low land 0x8000_0000) <> 0 then low - 0x1_0000_0000 else low in
  let high_signed = if (high land 0x8000_0000) <> 0 then high - 0x1_0000_0000 else high in
  let parts = HxArray.create () in
  ignore (HxArray.push parts low_signed);
  ignore (HxArray.push parts high_signed);
  parts

let i64ToDouble (low : int) (high : int) : float =
  let low64 = Int64.logand (Int64.of_int low) 0xFFFFFFFFL in
  let high64 =
    Int64.shift_left (Int64.logand (Int64.of_int high) 0xFFFFFFFFL) 32
  in
  Int64.float_of_bits (Int64.logor high64 low64)
