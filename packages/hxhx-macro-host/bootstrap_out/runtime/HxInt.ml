(* 32-bit Int semantics for reflaxe.ocaml.

   Why this exists:
   - Haxe `Int` is a signed 32-bit integer with overflow semantics.
   - OCaml `int` is word-sized (31/63-bit) and does not overflow at 32-bit.
   - To preserve Haxe semantics (and match upstream tests), we implement the
     core `Int` arithmetic + bitwise operators via `Int32` and convert back
     to OCaml `int`.

   Representation:
   - At runtime we still represent Haxe `Int` values as OCaml `int` for
     ergonomics and performance (e.g. printing, array indices).
   - Every operation that can overflow or depends on 32-bit bit patterns must
     go through `Int32` to preserve wraparound semantics.
*)

let mask_shift (n : int) : int =
  (* Haxe masks shift counts to 0..31. *)
  n land 31

let of_int (x : int) : int32 =
  Int32.of_int x

let to_int (x : int32) : int =
  Int32.to_int x

let add (a : int) (b : int) : int =
  to_int (Int32.add (of_int a) (of_int b))

let sub (a : int) (b : int) : int =
  to_int (Int32.sub (of_int a) (of_int b))

let mul (a : int) (b : int) : int =
  to_int (Int32.mul (of_int a) (of_int b))

let div (a : int) (b : int) : int =
  (* Division overflows are unspecified in Haxe beyond the Int32 range; we keep
     the Int32 round-to-zero behavior by operating in Int32 space. *)
  to_int (Int32.div (of_int a) (of_int b))

let rem (a : int) (b : int) : int =
  to_int (Int32.rem (of_int a) (of_int b))

let neg (a : int) : int =
  to_int (Int32.neg (of_int a))

let logand (a : int) (b : int) : int =
  to_int (Int32.logand (of_int a) (of_int b))

let logor (a : int) (b : int) : int =
  to_int (Int32.logor (of_int a) (of_int b))

let logxor (a : int) (b : int) : int =
  to_int (Int32.logxor (of_int a) (of_int b))

let lognot (a : int) : int =
  to_int (Int32.lognot (of_int a))

let shl (a : int) (b : int) : int =
  to_int (Int32.shift_left (of_int a) (mask_shift b))

let shr (a : int) (b : int) : int =
  to_int (Int32.shift_right (of_int a) (mask_shift b))

let ushr (a : int) (b : int) : int =
  to_int (Int32.shift_right_logical (of_int a) (mask_shift b))

