(* Dynamic reflection helpers for reflaxe.ocaml.

   Why this exists
   --------------
   Haxe's `Reflect` API provides a dynamic escape hatch that many libraries use
   for "soft" integration points (plugins, JSON-ish objects, dynamic calls).

   In portable mode, we already represent anonymous structures as a string-keyed
   table of `Obj.t` values (see `HxAnon`). `Reflect.callMethod` must be able to
   call a function value that flows through that dynamic surface.

   What we implement (M10 bring-up slice)
   -------------------------------------
   - `callMethod(obj, fn, args)` with a small fixed arity window (0..5).

   Notes / limitations
   -------------------
   - We ignore `obj` for now. Many Haxe targets use it to bind `this` for
     unbound method references, but our current codegen tends to produce bound
     closures for `obj.method` already.
   - This is intentionally conservative. Grow arity and semantics only when
     portable fixtures or upstream gates require it. *)

let varargs_marker : Obj.t = Obj.repr (ref 0)
let varargs_void_marker : Obj.t = Obj.repr (ref 0)

let mk_varargs (marker : Obj.t) (f : Obj.t) : Obj.t =
  let o = Obj.new_block 0 2 in
  Obj.set_field o 0 marker;
  Obj.set_field o 1 f;
  o

let is_varargs (marker : Obj.t) (v : Obj.t) : bool =
  (not (Obj.is_int v))
  && Obj.tag v = 0
  && Obj.size v = 2
  && Obj.field v 0 == marker

let isFunction (v : Obj.t) : bool =
  if HxRuntime.is_null v then
    false
  else if is_varargs varargs_marker v || is_varargs varargs_void_marker v then
    true
  else if Obj.is_int v then
    false
  else
    Obj.tag v = Obj.closure_tag

(* `Reflect.compareMethods` / `same_closure` support (best-effort).

   Why
   - utest (and other portable code) compares function values to verify deep equality
     behavior for objects that contain callbacks.
   - Haxe semantics consider two member method closures equal if they refer to the same
     method on the same object, even if the closure value was re-created.

   How
   - Fast path: physical equality.
   - Varargs wrappers: compare underlying function value.
   - Closures: compare code pointer (field 0) and captured environment fields by
     physical equality. This approximates "same method + same receiver" for the common
     backend pattern where member closures capture `self` and nothing else.
   - Otherwise: false. *)
let rec same_closure (a : Obj.t) (b : Obj.t) : bool =
  if HxRuntime.is_null a || HxRuntime.is_null b then
    false
  else if a == b then
    true
  else if is_varargs varargs_marker a && is_varargs varargs_marker b then
    same_closure (Obj.field a 1) (Obj.field b 1)
  else if is_varargs varargs_void_marker a && is_varargs varargs_void_marker b then
    same_closure (Obj.field a 1) (Obj.field b 1)
  else if Obj.is_int a || Obj.is_int b then
    false
  else if Obj.tag a = Obj.closure_tag && Obj.tag b = Obj.closure_tag then
    let sa = Obj.size a in
    let sb = Obj.size b in
    if sa <> sb then
      false
    else if Obj.field a 0 != Obj.field b 0 then
      false
    else
      let rec loop i =
        if i >= sa then true else if Obj.field a i == Obj.field b i then loop (i + 1) else false
      in
      loop 1
  else
    false

(* `Reflect.makeVarArgs` support.

   The returned value is a special wrapper that our dynamic call path recognizes.
   Instead of spreading arguments by arity, we pass the "args array" directly to
   the underlying function `f : Array<Dynamic> -> Dynamic/Void`. *)

let makeVarArgs (f : Obj.t) : Obj.t =
  mk_varargs varargs_marker f

let makeVarArgsVoid (f : Obj.t) : Obj.t =
  mk_varargs varargs_void_marker f

let callMethod (_obj : Obj.t) (fn : Obj.t) (args : Obj.t HxArray.t) : Obj.t =
  if is_varargs varargs_marker fn then
    let f = Obj.field fn 1 in
    (Obj.magic f : Obj.t HxArray.t -> Obj.t) args
  else if is_varargs varargs_void_marker fn then (
    let f = Obj.field fn 1 in
    ignore ((Obj.magic f : Obj.t HxArray.t -> unit) args);
    HxRuntime.hx_null
  ) else
  let len = HxArray.length args in
  let a i = HxArray.get args i in
  match len with
  | 0 -> (Obj.magic fn : unit -> Obj.t) ()
  | 1 -> (Obj.magic fn : Obj.t -> Obj.t) (a 0)
  | 2 -> (Obj.magic fn : Obj.t -> Obj.t -> Obj.t) (a 0) (a 1)
  | 3 -> (Obj.magic fn : Obj.t -> Obj.t -> Obj.t -> Obj.t) (a 0) (a 1) (a 2)
  | 4 -> (Obj.magic fn : Obj.t -> Obj.t -> Obj.t -> Obj.t -> Obj.t) (a 0) (a 1) (a 2) (a 3)
  | 5 ->
      (Obj.magic fn : Obj.t -> Obj.t -> Obj.t -> Obj.t -> Obj.t -> Obj.t)
        (a 0) (a 1) (a 2) (a 3) (a 4)
  | _ -> failwith ("Reflect.callMethod: unsupported arity: " ^ string_of_int len)

(* `Reflect.compare` support (best-effort on `Obj.t`).

   Semantics used for Gate1:
   - null/null => 0
   - null/non-null => +/-1 (only required to be != 0)
   - Int/Float compare numerically (boxing rules match `HxRuntime.dynamic_equals`)
   - String compare lexicographically
   - Fallback: `Stdlib.compare` on `Obj.t` (platform-dependent) *)
let compare (a : Obj.t) (b : Obj.t) : int =
  let hx_null_string : string = Obj.magic HxRuntime.hx_null in
  let is_nullish (v : Obj.t) : bool =
    if HxRuntime.is_null v then
      true
    else if (not (Obj.is_int v)) && Obj.tag v = Obj.string_tag then
      let s : string = Obj.obj v in
      s == hx_null_string
    else
      false
  in
  let an = is_nullish a in
  let bn = is_nullish b in
  if an && bn then
    0
  else if an then
    -1
  else if bn then
    1
  else if HxRuntime.is_boxed_bool a || HxRuntime.is_boxed_bool b then
    Stdlib.compare (HxRuntime.unbox_bool_or_obj a) (HxRuntime.unbox_bool_or_obj b)
  else if Obj.is_int a then
    if Obj.is_int b then
      Stdlib.compare (Obj.obj a : int) (Obj.obj b : int)
    else if Obj.tag b = Obj.double_tag then
      Stdlib.compare (float_of_int (Obj.obj a : int)) (Obj.obj b : float)
    else
      Stdlib.compare a b
  else if Obj.tag a = Obj.double_tag then
    if Obj.is_int b then
      Stdlib.compare (Obj.obj a : float) (float_of_int (Obj.obj b : int))
    else if Obj.tag b = Obj.double_tag then
      Stdlib.compare (Obj.obj a : float) (Obj.obj b : float)
    else
      Stdlib.compare a b
  else if Obj.tag a = Obj.string_tag && Obj.tag b = Obj.string_tag then
    Stdlib.compare (Obj.obj a : string) (Obj.obj b : string)
  else
    Stdlib.compare a b

(* `Reflect.isEnumValue` support (minimal).

   Gate1 note: enum values crossing into `Dynamic` should be boxed via `HxEnum.box_if_needed`,
   which allows us to detect them reliably here. *)
let isEnumValue (v : Obj.t) : bool =
  if HxRuntime.is_null v then
    false
  else
    match HxEnum.name_opt v with
    | Some _ -> true
    | None -> false

(* `Reflect.isObject` support (best-effort, matches upstream unit expectations).

   Upstream tests treat strings as objects on this target. We also treat:
   - anonymous structures (`HxAnon`)
   - class instances (identified via `HxType.getClass`)
   - `Class<T>` / `Enum<T>` values (`HxType.class_` / `HxType.enum_`) *)
let isObject (v : Obj.t) : bool =
  if HxRuntime.is_null v then
    false
  else if isEnumValue v then
    false
  else if Obj.is_int v then
    false
  else
    let tag = Obj.tag v in
    if tag = Obj.double_tag then
      false
    else if tag = Obj.closure_tag then
      false
    else if tag = Obj.string_tag then
      true
    else if HxAnon.is_anon v then
      true
    else if not (HxRuntime.is_null (HxType.getClass v)) then
      true
    else
      let hx_null_string : string = Obj.magic HxRuntime.hx_null in
      let cn = HxType.getClassName v in
      if cn != hx_null_string then
        true
      else
        let en = HxType.getEnumName v in
        en != hx_null_string
