(* hxhx Stage3 provider for haxe.Int64.

   Haxe Int64 values use signed 64-bit, two's-complement arithmetic. OCaml's
   Stdlib.Int64 has the same value width and wrapping behavior, so this shim
   keeps values in that native carrier instead of approximating them with the
   platform-sized OCaml [int] type.

   Shared Haxe typing has already selected exact declarations such as
   [haxe.Int64.addInt] before this module is emitted. This module only supplies
   their target implementations; it does not inspect source operators or pick
   helpers by name at a call site.

   This remains a Stage3 bootstrap provider rather than the final shared
   reflaxe.ocaml Int64 representation. Its public functions are deliberately
   typed, contain no unchecked casts, and preserve the supported Haxe 4.3.7
   arithmetic behavior while the two host routes converge on one target core. *)

type t = Stdlib.Int64.t

type divmod = {
  quotient : t;
  modulus : t;
}

let low_word_mask = 0xffff_ffffL

let of_haxe_int (value : int) : t =
  Stdlib.Int64.of_int32 (Stdlib.Int64.to_int32 (Stdlib.Int64.of_int value))

let make (high : int) (low : int) : t =
  let high_bits = Stdlib.Int64.shift_left (Stdlib.Int64.of_int high) 32 in
  let low_bits = Stdlib.Int64.logand (Stdlib.Int64.of_int low) low_word_mask in
  Stdlib.Int64.logor high_bits low_bits

let ofInt (value : int) : t =
  of_haxe_int value

let fromFloat (value : float) : t =
  if
    Stdlib.Float.is_nan value
    || value >= 9_007_199_254_740_992.0
    || value <= -9_007_199_254_740_992.0
  then
    failwith "Overflow"
  else
    Stdlib.Int64.of_float value

let parseString (value : string) : t =
  Stdlib.Int64.of_string (Stdlib.String.trim value)

let toInt (value : t) : int =
  let narrowed = Stdlib.Int64.to_int32 value in
  if Stdlib.Int64.of_int32 narrowed <> value then
    failwith "Overflow"
  else
    Stdlib.Int32.to_int narrowed

let toStr (value : t) : string =
  Stdlib.Int64.to_string value

let getHigh (value : t) : int =
  Stdlib.Int64.to_int (Stdlib.Int64.shift_right value 32)

let getLow (value : t) : int =
  Stdlib.Int32.to_int (Stdlib.Int64.to_int32 value)

let isNeg (value : t) : bool =
  Stdlib.Int64.compare value 0L < 0

let isZero (value : t) : bool =
  value = 0L

let compare (left : t) (right : t) : int =
  Stdlib.Int64.compare left right

let ucompare (left : t) (right : t) : int =
  Stdlib.Int64.compare
    (Stdlib.Int64.logxor left Stdlib.Int64.min_int)
    (Stdlib.Int64.logxor right Stdlib.Int64.min_int)

let add (left : t) (right : t) : t =
  Stdlib.Int64.add left right

let addInt (value : t) (amount : int) : t =
  Stdlib.Int64.add value (of_haxe_int amount)

let sub (left : t) (right : t) : t =
  Stdlib.Int64.sub left right

let subInt (value : t) (amount : int) : t =
  Stdlib.Int64.sub value (of_haxe_int amount)

let intSub (value : int) (amount : t) : t =
  Stdlib.Int64.sub (of_haxe_int value) amount

let mul (left : t) (right : t) : t =
  Stdlib.Int64.mul left right

let mulInt (value : t) (amount : int) : t =
  Stdlib.Int64.mul value (of_haxe_int amount)

let neg (value : t) : t =
  Stdlib.Int64.neg value

let divMod (dividend : t) (divisor : t) : divmod =
  if divisor = 0L then
    failwith "divide by zero"
  else
    {
      quotient = Stdlib.Int64.div dividend divisor;
      modulus = Stdlib.Int64.rem dividend divisor;
    }

let div (left : t) (right : t) : t =
  (divMod left right).quotient

let divInt (value : t) (divisor : int) : t =
  div value (of_haxe_int divisor)

let intDiv (value : int) (divisor : t) : t =
  div (of_haxe_int value) divisor

let remainder (left : t) (right : t) : t =
  (divMod left right).modulus

let mod_ (left : t) (right : t) : t =
  remainder left right

let modInt (value : t) (divisor : int) : t =
  of_haxe_int (toInt (remainder value (of_haxe_int divisor)))

let intMod (value : int) (divisor : t) : t =
  of_haxe_int (toInt (remainder (of_haxe_int value) divisor))

let eq (left : t) (right : t) : bool =
  left = right

let eqInt (value : t) (other : int) : bool =
  value = of_haxe_int other

let neq (left : t) (right : t) : bool =
  left <> right

let neqInt (value : t) (other : int) : bool =
  value <> of_haxe_int other

let lt (left : t) (right : t) : bool =
  compare left right < 0

let ltInt (value : t) (other : int) : bool =
  lt value (of_haxe_int other)

let intLt (value : int) (other : t) : bool =
  lt (of_haxe_int value) other

let lte (left : t) (right : t) : bool =
  compare left right <= 0

let lteInt (value : t) (other : int) : bool =
  lte value (of_haxe_int other)

let intLte (value : int) (other : t) : bool =
  lte (of_haxe_int value) other

let gt (left : t) (right : t) : bool =
  compare left right > 0

let gtInt (value : t) (other : int) : bool =
  gt value (of_haxe_int other)

let intGt (value : int) (other : t) : bool =
  gt (of_haxe_int value) other

let gte (left : t) (right : t) : bool =
  compare left right >= 0

let gteInt (value : t) (other : int) : bool =
  gte value (of_haxe_int other)

let intGte (value : int) (other : t) : bool =
  gte (of_haxe_int value) other

let complement (value : t) : t =
  Stdlib.Int64.lognot value

let and_ (left : t) (right : t) : t =
  Stdlib.Int64.logand left right

let or_ (left : t) (right : t) : t =
  Stdlib.Int64.logor left right

let xor (left : t) (right : t) : t =
  Stdlib.Int64.logxor left right

let shl (value : t) (amount : int) : t =
  Stdlib.Int64.shift_left value (amount land 63)

let shr (value : t) (amount : int) : t =
  Stdlib.Int64.shift_right value (amount land 63)

let ushr (value : t) (amount : int) : t =
  Stdlib.Int64.shift_right_logical value (amount land 63)

let isInt64 (_value : Obj.t) : bool =
  true
