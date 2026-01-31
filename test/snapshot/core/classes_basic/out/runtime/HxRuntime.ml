(* Minimal runtime scaffolding for reflaxe.ocaml (WIP).
   This will grow as std/_std overrides land. *)

exception Hx_exception of Obj.t
exception Hx_break
exception Hx_continue
exception Hx_return of Obj.t

(* Sentinel used to represent Haxe `null` across otherwise non-nullable OCaml types.
   Must be a heap block (not an immediate like `()`) so it doesn't collide with
   immediate values such as `int`/`bool`. *)
let hx_null : Obj.t = Obj.repr (ref 0)

let is_null (v : Obj.t) : bool =
  v == hx_null

(* Nullable primitives

   Haxe allows `Null<Int>`, `Null<Float>`, and `Null<Bool>` to represent either:
   - `null`, or
   - a real primitive value.

   In OCaml, `int/float/bool` cannot safely hold a “null sentinel” (casting a heap
   pointer to an immediate and then using it as a primitive can segfault).

   We therefore represent nullable primitives as:
   - `hx_null` for null
   - `Obj.repr <primitive>` for non-null

   Codegen must unbox (`Obj.obj`) only after checking `is_null`. *)

let nullable_int_toStdString (v : Obj.t) : string =
  if is_null v then
    "null"
  else
    string_of_int (Obj.obj v)

let nullable_float_toStdString (v : Obj.t) : string =
  if is_null v then
    "null"
  else
    string_of_float (Obj.obj v)

let nullable_bool_toStdString (v : Obj.t) : string =
  if is_null v then
    "null"
  else
    string_of_bool (Obj.obj v)

let nullable_int_unwrap (v : Obj.t) : int =
  if is_null v then
    failwith "Null<Int> unwrap"
  else
    Obj.obj v

let nullable_float_unwrap (v : Obj.t) : float =
  if is_null v then
    failwith "Null<Float> unwrap"
  else
    Obj.obj v

let nullable_bool_unwrap (v : Obj.t) : bool =
  if is_null v then
    failwith "Null<Bool> unwrap"
  else
    Obj.obj v

let hx_throw (v : Obj.t) : 'a =
  raise (Hx_exception v)

let hx_try (f : unit -> 'a) (handler : Obj.t -> 'a) : 'a =
  try f () with
  | Hx_exception v -> handler v
  | Hx_break -> raise Hx_break
  | Hx_continue -> raise Hx_continue
  | Hx_return v -> raise (Hx_return v)
  | exn -> handler (Obj.repr exn)
