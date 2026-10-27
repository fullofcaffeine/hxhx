(* hxhx Stage3 provider for haxe.Int64.

   Haxe Int64 values use signed 64-bit, two's-complement arithmetic. OCaml's
   Stdlib.Int64 has the same value width and wrapping behavior, so every
   operation computes on that native type instead of approximating it with the
   platform-sized OCaml [int] type.

   Shared Haxe typing has already selected exact declarations such as
   [haxe.Int64.addInt] before this module is emitted. This module only supplies
   their target implementations; it does not inspect source operators or pick
   helpers by name at a call site.

   This remains a Stage3 bootstrap provider rather than the final shared
   reflaxe.ocaml Int64 representation. Its public functions are deliberately
   typed and preserve the supported Haxe 4.3.7 arithmetic behavior while the
   two host routes converge on one target core. The only Obj reads are in the
   Dynamic stringifier and each follows a matching runtime-shape check. *)

(* Haxe 4.3.7 models one Int64 as a reference to a mutable two-word object.
   Copying a reference shares the object, so a private set_low/set_high call is
   visible through every alias, while [copy] and every arithmetic operation
   return a new object. The record below has the same field order as the
   reflaxe.ocaml generated [Haxe_Int64.___int64_t] record: a per-allocation
   identity header naming [haxe._Int64.___Int64], then the signed high and low
   32-bit words. Arithmetic still runs on [Stdlib.Int64.t] so wrapping matches
   two's-complement Haxe semantics; [to_native] and [of_native] convert at the
   edge of each operation. *)
type t = {
  __hx_type : Obj.t;
  mutable high : int;
  mutable low : int;
}

type divmod = {
  quotient : t;
  modulus : t;
}

let class_name = "haxe._Int64.___Int64"

let low_word_mask = 0xffff_ffffL

(* Keep one stored word inside the signed Haxe Int32 range, wrapping modulo
   2^32 as [make] already does for its arguments. *)
let signed_word (value : int) : int =
  Stdlib.Int32.to_int (Stdlib.Int32.of_int value)

let of_words (high : int) (low : int) : t =
  {
    __hx_type = HxType.instance_marker class_name;
    high = signed_word high;
    low = signed_word low;
  }

let to_native (value : t) : Stdlib.Int64.t =
  let high_bits = Stdlib.Int64.shift_left (Stdlib.Int64.of_int value.high) 32 in
  let low_bits = Stdlib.Int64.logand (Stdlib.Int64.of_int value.low) low_word_mask in
  Stdlib.Int64.logor high_bits low_bits

let of_native (value : Stdlib.Int64.t) : t =
  of_words
    (Stdlib.Int64.to_int (Stdlib.Int64.shift_right value 32))
    (Stdlib.Int32.to_int (Stdlib.Int64.to_int32 value))

let of_haxe_int (value : int) : t =
  of_words (if signed_word value < 0 then -1 else 0) value

let make (high : int) (low : int) : t =
  of_words high low

let ofInt (value : int) : t =
  of_haxe_int value

let copy (value : t) : t =
  of_words value.high value.low

let fromFloat (value : float) : t =
  if
    Stdlib.Float.is_nan value
    || value >= 9_007_199_254_740_992.0
    || value <= -9_007_199_254_740_992.0
  then
    failwith "Overflow"
  else
    of_native (Stdlib.Int64.of_float value)

let parseString (value : string) : t =
  of_native (Stdlib.Int64.of_string (Stdlib.String.trim value))

let toInt (value : t) : int =
  let high = value.high in
  let low = value.low in
  if high <> (if low < 0 then -1 else 0) then
    failwith "Overflow"
  else
    low

let toStr (value : t) : string =
  Stdlib.Int64.to_string (to_native value)

let getHigh (value : t) : int =
  value.high

let getLow (value : t) : int =
  value.low

(* Shared Haxe typing selects these declarations for .high and .low.
   They expose the same signed words as the public helpers above; no source
   property lookup or numeric policy is inferred by this native boundary. *)
let get_high = getHigh
let get_low = getLow

(* Shared Haxe typing selects these private setters for code such as
   haxe.io.FPHelper. Like Haxe's [this.high = x], they change the existing
   object in place, so aliases observe the new word and copies do not. The
   result is the stored word, matching the value of a Haxe assignment. *)
let set_high (value : t) (word : int) : int =
  let stored = signed_word word in
  value.high <- stored;
  stored

let set_low (value : t) (word : int) : int =
  let stored = signed_word word in
  value.low <- stored;
  stored

(* Haxe's Int64 object prints itself through Int64.toStr, so Std.string and
   Dynamic printing show the decimal value. HxDynamic calls this adapter only
   after the identity header names [class_name]; the layout check below keeps
   each Obj.obj read behind a matching runtime-shape check. *)
let () =
  HxDynamic.register_class_stringifier class_name (fun (dynamic : Obj.t) ->
      if
        Obj.is_block dynamic && Obj.tag dynamic = 0 && Obj.size dynamic = 3
        && Obj.is_int (Obj.field dynamic 1)
        && Obj.is_int (Obj.field dynamic 2)
      then
        toStr
          (of_words (Obj.obj (Obj.field dynamic 1) : int)
             (Obj.obj (Obj.field dynamic 2) : int))
      else
        class_name)

(* The operations below read each operand once, compute on the native 64-bit
   carrier, and allocate a new object for every Int64 result. None of them
   mutates an operand, matching Haxe's value-producing Int64 operators. *)
let lift1 (operation : Stdlib.Int64.t -> Stdlib.Int64.t) (value : t) : t =
  of_native (operation (to_native value))

let lift2 (operation : Stdlib.Int64.t -> Stdlib.Int64.t -> Stdlib.Int64.t)
    (left : t) (right : t) : t =
  of_native (operation (to_native left) (to_native right))

let isNeg (value : t) : bool =
  value.high < 0

let isZero (value : t) : bool =
  value.high = 0 && value.low = 0

let compare (left : t) (right : t) : int =
  Stdlib.Int64.compare (to_native left) (to_native right)

let ucompare (left : t) (right : t) : int =
  Stdlib.Int64.compare
    (Stdlib.Int64.logxor (to_native left) Stdlib.Int64.min_int)
    (Stdlib.Int64.logxor (to_native right) Stdlib.Int64.min_int)

let add (left : t) (right : t) : t =
  lift2 Stdlib.Int64.add left right

let addInt (value : t) (amount : int) : t =
  add value (of_haxe_int amount)

let sub (left : t) (right : t) : t =
  lift2 Stdlib.Int64.sub left right

let subInt (value : t) (amount : int) : t =
  sub value (of_haxe_int amount)

let intSub (value : int) (amount : t) : t =
  sub (of_haxe_int value) amount

let mul (left : t) (right : t) : t =
  lift2 Stdlib.Int64.mul left right

let mulInt (value : t) (amount : int) : t =
  mul value (of_haxe_int amount)

let neg (value : t) : t =
  lift1 Stdlib.Int64.neg value

let divMod (dividend : t) (divisor : t) : divmod =
  if isZero divisor then
    failwith "divide by zero"
  else
    let native_dividend = to_native dividend in
    let native_divisor = to_native divisor in
    {
      quotient = of_native (Stdlib.Int64.div native_dividend native_divisor);
      modulus = of_native (Stdlib.Int64.rem native_dividend native_divisor);
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

(* Haxe compares Int64 values by their 64 bits, never by object identity. *)
let eq (left : t) (right : t) : bool =
  left.high = right.high && left.low = right.low

let eqInt (value : t) (other : int) : bool =
  eq value (of_haxe_int other)

let neq (left : t) (right : t) : bool =
  not (eq left right)

let neqInt (value : t) (other : int) : bool =
  not (eqInt value other)

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
  lift1 Stdlib.Int64.lognot value

let and_ (left : t) (right : t) : t =
  lift2 Stdlib.Int64.logand left right

let or_ (left : t) (right : t) : t =
  lift2 Stdlib.Int64.logor left right

let xor (left : t) (right : t) : t =
  lift2 Stdlib.Int64.logxor left right

let shl (value : t) (amount : int) : t =
  lift1 (fun native -> Stdlib.Int64.shift_left native (amount land 63)) value

let shr (value : t) (amount : int) : t =
  lift1 (fun native -> Stdlib.Int64.shift_right native (amount land 63)) value

let ushr (value : t) (amount : int) : t =
  lift1 (fun native -> Stdlib.Int64.shift_right_logical native (amount land 63)) value

(* Upstream answers Std.isOfType(value, ___Int64). The identity header written
   by [of_words] is the runtime class fact this check reads. *)
let isInt64 (value : Obj.t) : bool =
  let value_class = HxType.getClass value in
  (not (HxRuntime.is_null value_class))
  && HxType.getClassName value_class = class_name
