(* Minimal `Type.*` runtime helpers for reflaxe.ocaml (WIP).

   Why this exists
   - Haxe's `Type` API is `extern` and requires target/runtime support.
   - Even for "portable mode", some reflection is needed for real-world code and
     upstream test workloads (e.g. `Type.getClassName`, `Type.resolveClass`).

   Scope (current milestone)
   - Class/enum values are represented as opaque `Obj.t` values created and
     interned by this module.
   - `resolveClass/resolveEnum` perform lookup in a runtime registry that is
     populated at program start by generated code (`HxTypeRegistry.init()`).

   Non-goals (yet)
   - Full reflection (fields, RTTI, `typeof`, `enumEq`, etc.). *)

(* A "null String" is represented as `Obj.magic HxRuntime.hx_null`. *)
let hx_null_string : string = Obj.magic HxRuntime.hx_null

let class_marker : Obj.t = Obj.repr (ref 0)
let enum_marker : Obj.t = Obj.repr (ref 0)

let mk_type_value (marker : Obj.t) (name : string) : Obj.t =
  let o = Obj.new_block 0 2 in
  Obj.set_field o 0 marker;
  Obj.set_field o 1 (Obj.repr name);
  o

let is_type_value (marker : Obj.t) (v : Obj.t) : bool =
  (not (Obj.is_int v)) && Obj.size v = 2 && Obj.field v 0 == marker

let type_value_name (marker : Obj.t) (v : Obj.t) : string =
  if is_type_value marker v then
    Obj.obj (Obj.field v 1)
  else
    hx_null_string

let classes : (string, Obj.t) Hashtbl.t = Hashtbl.create 251
let enums : (string, Obj.t) Hashtbl.t = Hashtbl.create 251

let class_ (name : string) : Obj.t =
  match Hashtbl.find_opt classes name with
  | Some v -> v
  | None ->
      let v = mk_type_value class_marker name in
      Hashtbl.add classes name v;
      v

let enum_ (name : string) : Obj.t =
  match Hashtbl.find_opt enums name with
  | Some v -> v
  | None ->
      let v = mk_type_value enum_marker name in
      Hashtbl.add enums name v;
      v

let getClassName (c : Obj.t) : string =
  if HxRuntime.is_null c then
    hx_null_string
  else
    type_value_name class_marker c

let getEnumName (e : Obj.t) : string =
  if HxRuntime.is_null e then
    hx_null_string
  else
    type_value_name enum_marker e

let resolveClass (name : string) : Obj.t =
  match Hashtbl.find_opt classes name with
  | Some v -> v
  | None -> HxRuntime.hx_null

let resolveEnum (name : string) : Obj.t =
  match Hashtbl.find_opt enums name with
  | Some v -> v
  | None -> HxRuntime.hx_null

(* Runtime class identity for `Type.getClass`.

   Our compiled class instances use OCaml records, and we use `Obj.magic` for
   inheritance/interface upcasts. This means the only reliable way to identify
   the most-derived class at runtime is to store a class value directly on the
   instance.

   Invariants enforced by codegen:
   - All class instance records have a first field named `__hx_type : Obj.t`.
   - That field stores the interned class value created by `class_ "<pack.Type>"`.
*)
let getClass (o : Obj.t) : Obj.t =
  if HxRuntime.is_null o then
    HxRuntime.hx_null
  else if Obj.is_int o then
    HxRuntime.hx_null
  else
    try
      let c = Obj.field o 0 in
      if is_type_value class_marker c then c else HxRuntime.hx_null
    with _ ->
      HxRuntime.hx_null
