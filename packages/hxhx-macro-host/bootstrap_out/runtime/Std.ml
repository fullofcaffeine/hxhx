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
   - `Std.string` delegates to `HxRuntime.dynamic_toStdString`, which understands
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
  HxRuntime.dynamic_toStdString v

let int (x : float) : int =
  (* Haxe: rounded towards 0. *)
  try int_of_float x with _ -> 0

let parseInt (x : string) : Obj.t =
  if x == hx_null_string then
    HxRuntime.hx_null
  else
    let len = String.length x in
    let i = ref 0 in
    while !i < len && is_space x.[!i] do
      incr i
    done;
    if !i >= len then
      HxRuntime.hx_null
    else
      let sign_start = !i in
      if x.[!i] = '+' || x.[!i] = '-' then incr i;
      if !i + 1 < len && x.[!i] = '0' && (x.[!i + 1] = 'x' || x.[!i + 1] = 'X') then (
        (* Hex: include optional sign + 0x prefix, then scan hex digits. *)
        i := !i + 2;
        let digits_start = !i in
        while !i < len && is_hex_digit x.[!i] do
          incr i
        done;
        if !i = digits_start then
          (* Haxe says this is "unspecified"; returning null is a safe default. *)
          HxRuntime.hx_null
        else
          let s = String.sub x sign_start (!i - sign_start) in
          match Stdlib.int_of_string_opt s with
          | Some v -> Obj.repr v
          | None -> HxRuntime.hx_null)
      else (
        (* Decimal: scan digits; stop at first invalid character. *)
        let digits_start = !i in
        while !i < len && is_digit x.[!i] do
          incr i
        done;
        if !i = digits_start then
          HxRuntime.hx_null
        else
          let s = String.sub x sign_start (!i - sign_start) in
          match Stdlib.int_of_string_opt s with
          | Some v -> Obj.repr v
          | None -> HxRuntime.hx_null)

let parseFloat (x : string) : float =
  if x == hx_null_string then
    nan
  else
    let len = String.length x in
    let i = ref 0 in
    while !i < len && is_space x.[!i] do
      incr i
    done;
    if !i >= len then
      nan
    else
      let start = !i in
      if x.[!i] = '+' || x.[!i] = '-' then incr i;

      let digits_before_start = !i in
      while !i < len && is_digit x.[!i] do
        incr i
      done;
      let has_digits_before = !i > digits_before_start in

      let has_dot = !i < len && x.[!i] = '.' in
      if has_dot then incr i;

      let digits_after_start = !i in
      while !i < len && is_digit x.[!i] do
        incr i
      done;
      let has_digits_after = has_dot && !i > digits_after_start in

      if not has_digits_before && not has_digits_after then
        nan
      else (
        (* Exponent: include only if it has at least one digit. Otherwise stop before 'e'. *)
        let end_before_exp = !i in
        if !i < len && (x.[!i] = 'e' || x.[!i] = 'E') then (
          let exp_i = ref (!i + 1) in
          if !exp_i < len && (x.[!exp_i] = '+' || x.[!exp_i] = '-') then incr exp_i;
          let exp_digits_start = !exp_i in
          while !exp_i < len && is_digit x.[!exp_i] do
            incr exp_i
          done;
          if !exp_i > exp_digits_start then
            i := !exp_i
          else
            i := end_before_exp)
        else
          ();

        let s = String.sub x start (!i - start) in
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
