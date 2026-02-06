(* Minimal runtime scaffolding for reflaxe.ocaml (WIP).
   This will grow as std/_std overrides land. *)

(* Haxe `throw` is not restricted to OCaml exception types; it can throw any value.
   We therefore wrap thrown payloads in a dedicated runtime exception that carries:
   - the raw value as `Obj.t` (so we can transport anything), and
   - a list of "type tags" used to implement typed catches (`catch (e:T)`).

   Why tags?
   - OCaml's runtime representation cannot reliably distinguish some Haxe primitives
     by `Obj` inspection alone (e.g. `int` and `bool` are both immediates).
   - We want typed catches to be predictable under `-warn-error` without requiring
     full RTTI / reflection in early milestones.

   The compiler backend is responsible for producing best-effort tags based on the
   *static* type of the thrown expression (and for classes, including supertypes and
   implemented interfaces). *)
exception Hx_exception of Obj.t * string list
exception Hx_break
exception Hx_continue
exception Hx_return of Obj.t

(* Sentinel used to represent Haxe `null` across otherwise non-nullable OCaml types.
   Must be a heap block (not an immediate like `()`) so it doesn't collide with
   immediate values such as `int`/`bool`. *)
let hx_null : Obj.t = Obj.repr (ref 0)

let is_null (v : Obj.t) : bool =
  v == hx_null

(* Boxing for booleans stored as `Obj.t`.

   Why:
   - OCaml represents `bool` and `int` as immediates. If we store `true` as
     `Obj.repr true`, it is indistinguishable from the integer `1`.
   - Typed catches (`catch (e:Bool)`) and `Std.isOfType` must never confuse a
     boolean with an integer.

   Strategy:
   - Any time a Haxe boolean needs to be represented as `Obj.t`, codegen should
     use `box_bool`.
   - Runtime helpers treat boxed booleans as booleans and do not rely on the
     immediate representation. *)

let bool_box_marker : Obj.t = Obj.repr (ref 0)

let is_boxed_bool (v : Obj.t) : bool =
  (not (Obj.is_int v)) && Obj.size v = 2 && Obj.field v 0 == bool_box_marker

let box_bool (b : bool) : Obj.t =
  let o = Obj.new_block 0 2 in
  Obj.set_field o 0 bool_box_marker;
  Obj.set_field o 1 (Obj.repr b);
  o

let unbox_bool_or_obj (v : Obj.t) : bool =
  if is_boxed_bool v then
    Obj.obj (Obj.field v 1)
  else
    Obj.obj v

(* Dynamic equality (`==`) for values carried as `Obj.t`.

   Why:
   - When values flow through `Dynamic` / `Std.Any` / `HxAnon` we represent them as `Obj.t`.
   - OCaml polymorphic equality (`=`) is structural and would make unrelated “objects”
     compare equal by shape. This breaks Haxe identity semantics (e.g. two distinct
     enum values with args, two distinct anonymous objects, etc.).
   - However, Haxe still expects *numeric* value equality across Int/Float, and string
     value equality.

   Semantics (best-effort, aligns with static targets like Neko/HL):
   - `null` compares equal only to `null` (including `Null<String>` sentinel).
   - Int/Float compare by numeric value (int coerces to float when needed).
   - Bool compares by value (requires boxing via `box_bool` when carried as `Obj.t`).
   - String compares by content (and treats the `Null<String>` sentinel as null).
   - Everything else compares by identity (physical equality). *)

let is_null_string_obj (v : Obj.t) : bool =
  if Obj.is_int v then
    false
  else if Obj.tag v = Obj.string_tag then
    let hx_null_string : string = Obj.magic hx_null in
    let s : string = Obj.obj v in
    s == hx_null_string
  else
    false

let dynamic_equals (a : Obj.t) (b : Obj.t) : bool =
  let a_is_null = is_null a || is_null_string_obj a in
  let b_is_null = is_null b || is_null_string_obj b in
  if a_is_null || b_is_null then
    a_is_null && b_is_null
  else if is_boxed_bool a || is_boxed_bool b then
    (is_boxed_bool a && is_boxed_bool b) && unbox_bool_or_obj a = unbox_bool_or_obj b
  else if Obj.is_int a then
    if Obj.is_int b then
      (Obj.obj a : int) = (Obj.obj b : int)
    else if Obj.tag b = Obj.double_tag then
      float_of_int (Obj.obj a : int) = (Obj.obj b : float)
    else
      false
  else if Obj.tag a = Obj.double_tag then
    if Obj.is_int b then
      (Obj.obj a : float) = float_of_int (Obj.obj b : int)
    else if Obj.tag b = Obj.double_tag then
      (Obj.obj a : float) = (Obj.obj b : float)
    else
      false
  else if Obj.tag a = Obj.string_tag then
    if Obj.tag b = Obj.string_tag then
      (Obj.obj a : string) = (Obj.obj b : string)
    else
      false
  else
    a == b

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
    string_of_bool (unbox_bool_or_obj v)

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
    unbox_bool_or_obj v

(* Best-effort `Std.string` for values stored as `Obj.t`.

   This is primarily used when Haxe code concatenates `Dynamic` values into strings
   (including values extracted from anonymous structures via `Reflect.field` or
   `obj.field` on Dynamic).

   Limitations:
   - `bool` and `int` are both immediates in OCaml, so we treat all immediates as `int`.
     Typed (non-Dynamic) booleans are still printed correctly via `string_of_bool` in codegen. *)
let dynamic_toStdString (v : Obj.t) : string =
  if is_null v then
    "null"
  else if is_boxed_bool v then
    string_of_bool (unbox_bool_or_obj v)
  else if Obj.is_int v then
    string_of_int (Obj.obj v)
  else
    let tag = Obj.tag v in
    if tag = Obj.string_tag then
      let hx_null_string : string = Obj.magic hx_null in
      let s : string = Obj.obj v in
      if s == hx_null_string then "null" else s
    else if tag = Obj.double_tag then
      string_of_float (Obj.obj v)
    else
      "<object>"

let tags_has (tags : string list) (tag : string) : bool =
  List.exists (fun t -> t = tag) tags

let hx_throw_typed (v : Obj.t) (tags : string list) : 'a =
  raise (Hx_exception (v, tags))

let hx_throw (v : Obj.t) : 'a =
  hx_throw_typed v [ "Dynamic" ]

let hx_try (f : unit -> 'a) (handler : Obj.t -> 'a) : 'a =
  try f () with
  | Hx_exception (v, _tags) -> handler v
  | Hx_break -> raise Hx_break
  | Hx_continue -> raise Hx_continue
  | Hx_return v -> raise (Hx_return v)
  | exn -> handler (Obj.repr exn)
