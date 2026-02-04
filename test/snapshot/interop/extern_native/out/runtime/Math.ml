(* OCaml runtime implementation for the Haxe `Math` extern.

   Why:
   - Upstream Haxe declares `Math` as an extern class.
   - For a custom target like OCaml we must provide the actual implementation.

   Notes:
   - This is a portable surface: we keep Haxe `Math` semantics where possible.
   - Some behaviors are explicitly "unspecified" by Haxe for out-of-range
     values (e.g. converting infinities to Int).
*)

let pi : float =
  4.0 *. atan 1.0

let negative_infinity : float =
  neg_infinity

let positive_infinity : float =
  infinity

let nan : float =
  nan

let abs (v : float) : float =
  Float.abs v

let min (a : float) (b : float) : float =
  if Float.is_nan a || Float.is_nan b then nan else Float.min a b

let max (a : float) (b : float) : float =
  if Float.is_nan a || Float.is_nan b then nan else Float.max a b

let sin (v : float) : float = Stdlib.sin v
let cos (v : float) : float = Stdlib.cos v
let tan (v : float) : float = Stdlib.tan v
let asin (v : float) : float = Stdlib.asin v
let acos (v : float) : float = Stdlib.acos v
let atan (v : float) : float = Stdlib.atan v
let atan2 (y : float) (x : float) : float = Stdlib.atan2 y x
let exp (v : float) : float = Stdlib.exp v
let log (v : float) : float = Stdlib.log v
let pow (v : float) (e : float) : float = v ** e
let sqrt (v : float) : float = Stdlib.sqrt v

let round (v : float) : int =
  (* Haxe: ties are rounded up (towards +infinity). *)
  int_of_float (Stdlib.floor (v +. 0.5))

let floor (v : float) : int =
  int_of_float (Stdlib.floor v)

let ceil (v : float) : int =
  int_of_float (Stdlib.ceil v)

let fround (v : float) : float =
  (* TODO(M11): Implement IEEE-754 float32 rounding.
     OCaml's `float` is a 64-bit double; for now keep as identity. *)
  v

let isNaN (v : float) : bool =
  Float.is_nan v

let isFinite (v : float) : bool =
  Float.is_finite v

let () =
  (* Seed once per process. *)
  Random.self_init ()

let random () : float =
  (* Matches common Haxe target behavior: pseudorandom in [0,1). *)
  Random.float 1.0
