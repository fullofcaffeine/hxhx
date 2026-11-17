(* OCaml runtime implementation for the Haxe `Std` extern.

   Why:
   - Upstream Haxe declares `Std` as an extern class, so every target must supply
     an implementation.
   - This backend emits calls like `Std.parseInt`, `Std.string`, etc.

   What:
   - Minimal, best-effort implementations of the `Std` surface used by the Haxe
     standard library and common user code.

   How:
   - Nullable primitives (`Null<Int>`) are represented as `Obj.t`:
     - `HxRuntime.hx_null` for null
     - `Obj.repr <primitive>` for non-null
   - `Std.string` delegates to `HxDynamic.toStdString`, which understands
     the backend's null/boxing representation for Dynamic values.

   Notes:
   - Some behaviors are "unspecified" by Haxe (e.g. parse overflow / int/float
     conversion edge cases). We keep conservative behavior and avoid raising.
*)

let hx_null_string : string =
  Obj.magic HxRuntime.hx_null

let is_space (c : char) : bool =
  c = ' ' || c = '\t' || c = '\n' || c = '\r' || c = '\012'

let is_digit (c : char) : bool =
  c >= '0' && c <= '9'

let is_hex_digit (c : char) : bool =
  (c >= '0' && c <= '9')
  || (c >= 'a' && c <= 'f')
  || (c >= 'A' && c <= 'F')

let string (v : Obj.t) : string =
  HxDynamic.toStdString v

let int (x : float) : int =
  (* Haxe: truncate toward 0, then wrap into the signed 32-bit Int range, as
     upstream eval does: Std.int(4294967295.0) is -1 and Std.int(2^31) is
     -2147483648. `int_of_float` never raises. NaN, +/-Infinity, and
     |x| >= 2^63 have no defined OCaml result: what `int_of_float` returns
     there is the CPU's conversion (NaN gives 0 on arm64 and x86-64), the same
     primitive eval uses. Reviewed under the gate in
     docs/00-project/FLOAT_NUMERIC_REVIEW_GATE.md; the answers are recorded
     on Bead haxe_ocaml-3lpr4. *)
  Int32.to_int (Int32.of_int (int_of_float x))

let parseInt (x : string) : Obj.t =
  if x == hx_null_string then
    HxRuntime.hx_null
  else
    let len = Stdlib.String.length x in
    let i = ref 0 in
    while !i < len && is_space (Stdlib.String.get x (!i)) do
      incr i
    done;
    if !i >= len then
      HxRuntime.hx_null
    else
      let sign_start = !i in
      if (Stdlib.String.get x (!i)) = '+' || (Stdlib.String.get x (!i)) = '-' then incr i;
      if !i + 1 < len && (Stdlib.String.get x (!i)) = '0' && (Stdlib.String.get x (!i + 1) = 'x' || (Stdlib.String.get x (!i + 1)) = 'X') then (
        (* Hex: include optional sign + 0x prefix, then scan hex digits. *)
        i := !i + 2;
        let digits_start = !i in
        while !i < len && is_hex_digit (Stdlib.String.get x (!i)) do
          incr i
        done;
        if !i = digits_start then
          (* Haxe says this is "unspecified"; returning null is a safe default. *)
          HxRuntime.hx_null
        else
          let s = Stdlib.String.sub x sign_start (!i - sign_start) in
          match Stdlib.int_of_string_opt s with
          | Some v -> Obj.repr v
          | None -> HxRuntime.hx_null)
      else (
        (* Decimal: scan digits; stop at first invalid character. *)
        let digits_start = !i in
        while !i < len && is_digit (Stdlib.String.get x (!i)) do
          incr i
        done;
        if !i = digits_start then
          HxRuntime.hx_null
        else
          let s = Stdlib.String.sub x sign_start (!i - sign_start) in
          match Stdlib.int_of_string_opt s with
          | Some v -> Obj.repr v
          | None -> HxRuntime.hx_null)

let parseFloat (x : string) : float =
  if x == hx_null_string then
    nan
  else
    let len = Stdlib.String.length x in
    let i = ref 0 in
    while !i < len && is_space (Stdlib.String.get x (!i)) do
      incr i
    done;
    if !i >= len then
      nan
    else
      let start = !i in
      if (Stdlib.String.get x (!i)) = '+' || (Stdlib.String.get x (!i)) = '-' then incr i;

      let digits_before_start = !i in
      while !i < len && is_digit (Stdlib.String.get x (!i)) do
        incr i
      done;
      let has_digits_before = !i > digits_before_start in

      let has_dot = !i < len && (Stdlib.String.get x (!i)) = '.' in
      if has_dot then incr i;

      let digits_after_start = !i in
      while !i < len && is_digit (Stdlib.String.get x (!i)) do
        incr i
      done;
      let has_digits_after = has_dot && !i > digits_after_start in

      if not has_digits_before && not has_digits_after then
        nan
      else (
        (* Exponent: include only if it has at least one digit. Otherwise stop before 'e'. *)
        let end_before_exp = !i in
        if !i < len && (Stdlib.String.get x (!i) = 'e' || (Stdlib.String.get x (!i)) = 'E') then (
          let exp_i = ref (!i + 1) in
          if !exp_i < len && (Stdlib.String.get x (!exp_i) = '+' || (Stdlib.String.get x (!exp_i)) = '-') then incr exp_i;
          let exp_digits_start = !exp_i in
          while !exp_i < len && is_digit (Stdlib.String.get x (!exp_i)) do
            incr exp_i
          done;
          if !exp_i > exp_digits_start then
            i := !exp_i
          else
            i := end_before_exp)
        else
          ();

        let s = Stdlib.String.sub x start (!i - start) in
        try float_of_string s with _ -> nan)

let () =
  (* Seed once per process. *)
  Random.self_init ()

let random (x : int) : int =
  if x <= 1 then 0 else Random.int x

let isOfType (v : Obj.t) (t : Obj.t) : bool =
  HxType.isOfType v t

let is (v : Obj.t) (t : Obj.t) : bool =
  (* `Std.is` is deprecated upstream, but still exists. *)
  isOfType v t

let downcast (value : 'a) (c : Obj.t) : 'b =
  let v = Obj.repr value in
  if isOfType v c then
    Obj.magic value
  else
    Obj.magic HxRuntime.hx_null

let instance (value : 'a) (c : Obj.t) : 'b =
  downcast value c
