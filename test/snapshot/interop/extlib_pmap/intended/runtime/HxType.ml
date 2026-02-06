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
let class_tags : (string, string list) Hashtbl.t = Hashtbl.create 251
let class_supers : (string, Obj.t) Hashtbl.t = Hashtbl.create 251
let class_instance_fields : (string, string list) Hashtbl.t = Hashtbl.create 251
let class_static_fields : (string, string list) Hashtbl.t = Hashtbl.create 251
let class_ctors : (string, Obj.t HxArray.t -> Obj.t) Hashtbl.t = Hashtbl.create 251
let class_empty_ctors : (string, unit -> Obj.t) Hashtbl.t = Hashtbl.create 251
let enum_ctors : (string, string list) Hashtbl.t = Hashtbl.create 251
let enum_ctor_fns : (string, Obj.t HxArray.t -> Obj.t) Hashtbl.t = Hashtbl.create 251

let enum_ctor_key (enum_name : string) (ctor_name : string) : string =
  enum_name ^ "." ^ ctor_name

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

(* Typed catches (M10): runtime tags for class instances.

   Why:
   - `throw` can be typed as a supertype (`Base`) or even `Dynamic`, while the
     runtime value might be a subclass (`Child`). Typed catches (`catch (e:Child)`)
     must match based on runtime type identity, not just the throw site's static type.

   Strategy:
   - Codegen stores a per-instance `__hx_type : Obj.t` marker (see `getClass` below).
   - Generated `HxTypeRegistry.init()` registers the full tag set for each compiled
     class name via `register_class_tags`.
   - At throw time, codegen calls `hx_throw_typed_rtti`, which merges static tags
     with runtime tags derived from the payload value.

   Note:
   - We intentionally avoid trying to infer tags from OCaml runtime shapes for
     immediates (e.g. `int` vs `bool`), because that would be ambiguous and lead
     to incorrect typed-catch matches. *)

let register_class_tags (name : string) (tags : string list) : unit =
  Hashtbl.replace class_tags name tags

(* `Type.getSuperClass` support (minimal).

   Why
   - Some portable code and upstream unit tests query inheritance at runtime.
   - OCaml records do not preserve inheritance metadata, so we register the superclass
     relation at compile time in `HxTypeRegistry.init()`.

   Semantics
   - Returns `null` if `c` has no known superclass or `c` is null/unknown. *)
let register_class_super (name : string) (super_ : Obj.t) : unit =
  Hashtbl.replace class_supers name super_

let getSuperClass (c : Obj.t) : Obj.t =
  if HxRuntime.is_null c then
    HxRuntime.hx_null
  else
    let name = getClassName c in
    if HxRuntime.is_null (Obj.repr name) then
      HxRuntime.hx_null
    else
      match Hashtbl.find_opt class_supers name with
      | Some s -> s
      | None -> HxRuntime.hx_null

(* Minimal `Type.getInstanceFields` / `Type.getClassFields` support.

   Why
   - Upstream test harnesses and portable code frequently ask for "what fields
     does this class have?", and expect DCE-filtered results.
   - OCaml records do not carry reflection metadata, so we generate and register
     field name lists at compile time in `HxTypeRegistry.init()`.

   Semantics (mirrors Haxe)
   - `getInstanceFields(C)` includes inherited instance fields.
   - `getClassFields(C)` includes only fields declared on `C` (no inheritance).
   - `null` / unknown classes return an empty array. *)

let register_class_instance_fields (name : string) (fields : string list) : unit =
  Hashtbl.replace class_instance_fields name fields

let register_class_static_fields (name : string) (fields : string list) : unit =
  Hashtbl.replace class_static_fields name fields

(* `Type.createInstance` support (minimal).

   Why
   - Upstream tests and portable code frequently construct types from runtime class
     values (e.g. macro toolchains).
   - In OCaml we compile constructors as regular functions with fixed arity, so a
     generic "apply array of args" requires metadata.

   Strategy
   - Generated `HxTypeRegistry.init()` registers, for each compiled class name, a
     closure of type `Obj.t HxArray.t -> Obj.t` that:
       - validates required arg count,
       - pads omitted optional args with `hx_null` (to avoid partial application),
       - unboxes dynamic primitives (notably boxed Bool),
       - calls the class's emitted `create` function and returns the instance as `Obj.t`.
   - `createInstance` looks up and invokes that closure.

   Note
   - This intentionally supports only compiled classes. Extern/native classes should
     be handled separately via OCaml-native APIs. *)

let register_class_ctor (name : string) (ctor : Obj.t HxArray.t -> Obj.t) : unit =
  Hashtbl.replace class_ctors name ctor

let register_class_empty_ctor (name : string) (ctor : unit -> Obj.t) : unit =
  Hashtbl.replace class_empty_ctors name ctor

let createInstance (c : Obj.t) (args : Obj.t HxArray.t) : Obj.t =
  if HxRuntime.is_null c then
    HxRuntime.hx_null
  else
    let name = getClassName c in
    if HxRuntime.is_null (Obj.repr name) then
      HxRuntime.hx_null
    else
      match Hashtbl.find_opt class_ctors name with
      | Some ctor -> ctor args
      | None -> HxRuntime.hx_null

let createEmptyInstance (c : Obj.t) : Obj.t =
  if HxRuntime.is_null c then
    HxRuntime.hx_null
  else
    let name = getClassName c in
    if HxRuntime.is_null (Obj.repr name) then
      HxRuntime.hx_null
    else
      match Hashtbl.find_opt class_empty_ctors name with
      | Some ctor -> ctor ()
      | None -> HxRuntime.hx_null

let fields_to_hx_array (fields : string list) : string HxArray.t =
  let a = HxArray.create () in
  List.iter (fun f -> ignore (HxArray.push a f)) fields;
  a

let getInstanceFields (c : Obj.t) : string HxArray.t =
  if HxRuntime.is_null c then
    fields_to_hx_array []
  else
    let name = getClassName c in
    if HxRuntime.is_null (Obj.repr name) then
      fields_to_hx_array []
    else
      match Hashtbl.find_opt class_instance_fields name with
      | Some fields -> fields_to_hx_array fields
      | None -> fields_to_hx_array []

let getClassFields (c : Obj.t) : string HxArray.t =
  if HxRuntime.is_null c then
    fields_to_hx_array []
  else
    let name = getClassName c in
    if HxRuntime.is_null (Obj.repr name) then
      fields_to_hx_array []
    else
      match Hashtbl.find_opt class_static_fields name with
      | Some fields -> fields_to_hx_array fields
      | None -> fields_to_hx_array []

(* `Type.getEnumConstructs` support. *)

let register_enum_ctors (name : string) (ctors : string list) : unit =
  Hashtbl.replace enum_ctors name ctors

(* `Type.createEnum` / `Type.createEnumIndex` support.

   Why
   - Portable code can pass `Enum<T>` values through `Dynamic` (e.g. `var e:Dynamic = MyEnum`)
     and still call `Type.createEnum(e, ...)`.
   - OCaml variants have no “enum object” at runtime, so we register constructor closures
     at compile time (see generated `HxTypeRegistry.init()`).

   Semantics (best-effort, matches upstream unit tests)
   - Returns `null` when `e` is null or unknown.
   - Throws (via `failwith`) when required constructor args are missing (enforced by the
     generated constructor closures). *)

let register_enum_ctor (enum_name : string) (ctor_name : string)
    (f : Obj.t HxArray.t -> Obj.t) : unit =
  Hashtbl.replace enum_ctor_fns (enum_ctor_key enum_name ctor_name) f

let createEnum (e : Obj.t) (ctor_name : string) (params : Obj.t HxArray.t) : Obj.t =
  if HxRuntime.is_null e then
    HxRuntime.hx_null
  else if is_type_value enum_marker e then
    let enum_name = type_value_name enum_marker e in
    match Hashtbl.find_opt enum_ctor_fns (enum_ctor_key enum_name ctor_name) with
    | Some f -> f params
    | None -> HxRuntime.hx_null
  else
    HxRuntime.hx_null

let createEnumIndex (e : Obj.t) (idx : int) (params : Obj.t HxArray.t) : Obj.t =
  if HxRuntime.is_null e then
    HxRuntime.hx_null
  else if is_type_value enum_marker e then
    let enum_name = type_value_name enum_marker e in
    match Hashtbl.find_opt enum_ctors enum_name with
    | None -> HxRuntime.hx_null
    | Some ctors ->
        if idx < 0 || idx >= List.length ctors then
          HxRuntime.hx_null
        else
          let ctor_name = List.nth ctors idx in
          createEnum e ctor_name params
  else
    HxRuntime.hx_null

let getEnumConstructs (e : Obj.t) : string HxArray.t =
  if HxRuntime.is_null e then
    fields_to_hx_array []
  else
    let name = getEnumName e in
    if HxRuntime.is_null (Obj.repr name) then
      fields_to_hx_array []
    else
      match Hashtbl.find_opt enum_ctors name with
      | Some ctors -> fields_to_hx_array ctors
      | None -> fields_to_hx_array []

(* `Type.getEnum` / enum introspection support (minimal, dynamic-friendly).

   Why
   - Portable test harnesses (utest) call `Type.getEnum/enumIndex/enumParameters/enumConstructor`
     on values typed as `Dynamic`. This means we must operate on the dynamic (`Obj.t`)
     representation and handle boxed enum values.

   Strategy
   - Enum values that cross into `Dynamic` should be boxed via `HxEnum.box_if_needed` so we can:
     - recover the enum name (`HxEnum.name_opt`), and
     - inspect the raw OCaml variant payload for ctor index + args.
   - For non-boxed values, `enumIndex/enumParameters` still work best-effort by inspecting the
     raw OCaml value shape (int immediates and variant blocks). `getEnum/enumConstructor` need
     the enum name, so they return null/`null`-string when not boxed. *)

let getEnum (o : Obj.t) : Obj.t =
  if HxRuntime.is_null o then
    HxRuntime.hx_null
  else
    match HxEnum.name_opt o with
    | Some name -> enum_ name
    | None -> HxRuntime.hx_null

let enumIndex (o : Obj.t) : int =
  if HxRuntime.is_null o then
    -1
  else
    let v =
      match HxEnum.name_opt o with
      | Some _ -> Obj.field o 2
      | None -> o
    in
    if Obj.is_int v then
      (Obj.obj v : int)
    else
      Obj.tag v

let enumParameters (o : Obj.t) : Obj.t HxArray.t =
  let out = HxArray.create () in
  if HxRuntime.is_null o then
    out
  else
    let v =
      match HxEnum.name_opt o with
      | Some _ -> Obj.field o 2
      | None -> o
    in
    if Obj.is_int v then
      out
    else (
      let size = Obj.size v in
      for i = 0 to size - 1 do
        ignore (HxArray.push out (Obj.field v i))
      done;
      out)

let enumConstructor (o : Obj.t) : string =
  if HxRuntime.is_null o then
    hx_null_string
  else
    match HxEnum.name_opt o with
    | None -> hx_null_string
    | Some name ->
        let v = Obj.field o 2 in
        let idx =
          if Obj.is_int v then
            (Obj.obj v : int)
          else
            Obj.tag v
        in
        match Hashtbl.find_opt enum_ctors name with
        | None -> hx_null_string
        | Some ctors -> (
            try List.nth ctors idx with _ -> hx_null_string)

let merge_tags (a : string list) (b : string list) : string list =
  let seen : (string, unit) Hashtbl.t =
    Hashtbl.create (max 7 (List.length a + List.length b))
  in
  let add (acc : string list) (t : string) : string list =
    if Hashtbl.mem seen t then acc
    else (
      Hashtbl.add seen t ();
      t :: acc)
  in
  let acc = List.fold_left add [] a in
  let acc = List.fold_left add acc b in
  List.rev acc

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
  else if Obj.tag o <> 0 then
    (* Avoid treating arbitrary OCaml blocks (strings, floats, closures, etc.) as
       our "class instance record" representation. *)
    HxRuntime.hx_null
  else if Obj.size o < 1 then
    HxRuntime.hx_null
  else
    try
      let c = Obj.field o 0 in
      if is_type_value class_marker c then c else HxRuntime.hx_null
    with _ ->
      HxRuntime.hx_null

let tags_for_value (o : Obj.t) : string list =
  if HxRuntime.is_null o then
    []
  else if HxRuntime.is_boxed_bool o then
    [ "Bool" ]
  else if Obj.is_int o then
    (* Note: booleans carried as `Obj.t` must be boxed via `HxRuntime.box_bool`. *)
    [ "Int" ]
  else
    let tag = Obj.tag o in
    if tag = Obj.string_tag then
      [ "String" ]
    else if tag = Obj.double_tag then
      [ "Float" ]
    else
      match HxEnum.name_opt o with
      | Some name -> [ name ]
      | None ->
          let c = getClass o in
          if HxRuntime.is_null c then
            []
          else
            let name = getClassName c in
            if HxRuntime.is_null (Obj.repr name) then
              []
            else
              match Hashtbl.find_opt class_tags name with
              | Some tags -> tags
              | None -> []

(* `Std.isOfType` support (best-effort).

   Why:
   - Haxe stdlib frequently uses `Std.isOfType(v, SomeClass)` as a dynamic type test.
   - We already maintain class tag sets for typed catches; reuse those tags to implement
     inheritance-aware checks.

   Notes:
   - This currently focuses on class checks (the most common usage, and what's needed
     for `haxe.Exception.caught/thrown`).
   - When tag info is missing, we fall back to exact-class equality.
*)
let isOfType (v : Obj.t) (t : Obj.t) : bool =
  if HxRuntime.is_null v || HxRuntime.is_null t then
    false
  else if is_type_value class_marker t then
    let target = getClassName t in
    if HxRuntime.is_null (Obj.repr target) then
      false
    else
      let tags = tags_for_value v in
      if List.length tags = 0 then
        getClassName (getClass v) = target
      else
        List.exists (fun x -> x = target) tags
  else if is_type_value enum_marker t then
    let target = getEnumName t in
    if HxRuntime.is_null (Obj.repr target) then
      false
    else (
      match HxEnum.name_opt v with
      | Some name -> name = target
      | None -> false)
  else
    false

let hx_throw_typed_rtti (v : Obj.t) (static_tags : string list) : 'a =
  let runtime_tags = tags_for_value v in
  let tags = merge_tags static_tags runtime_tags in
  raise (HxRuntime.Hx_exception (v, tags))
