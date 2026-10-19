(* Independent observations of enum boxes, private class storage, and OCaml GC.
   Haxe selects names and ancestry in production; this observer supplies fixed
   descriptors solely to exercise the native representation boundary. *)
type native_record = { __hx_type : Obj.t; value : int }
type equality_variant = Atom | Payload of int

let require condition message = if not condition then failwith message
let no_class value = HxRuntime.is_null (HxType.getClass value)

let[@inline never] install_dead weak descriptor =
  let value = HxAnon.create_with_class descriptor in
  Weak.set weak 0 (Some value)

let () =
  (* Deliberately register out of order and initialize lazily. Native tags and
     Haxe indexes differ; allEnums must keep the compiler-provided mapping. *)
  let initialized = ref 0 in
  HxType.set_registry_init_hook (fun () ->
    incr initialized;
    HxType.register_enum_ctor_layout "observer.Choice" "Last" 3 (HxType.EnumImmediate 1);
    HxType.register_enum_ctor_layout "observer.Choice" "Payload" 0 (HxType.EnumBlock 0);
    HxType.register_enum_ctor_layout "observer.Choice" "First" 1 (HxType.EnumImmediate 0);
    HxType.register_enum_ctor_layout "observer.Choice" "More" 2 (HxType.EnumBlock 1);
    HxType.register_enum_ctor_layout "observer.Other" "First" 0 (HxType.EnumImmediate 0));
  let descriptor = HxType.enum_ "observer.Choice" in
  let constants = HxType.allEnums descriptor in
  let repeated = HxType.allEnums descriptor in
  require (!initialized = 1) "enum query did not initialize once";
  require (HxArray.length constants = 2) "enum query included payload constructors";
  require (HxArray.get constants 0 == HxEnum.box_if_needed "observer.Choice" (Obj.repr 0))
    "first constant lost physical singleton identity";
  require (HxArray.get constants 1 == HxEnum.box_if_needed "observer.Choice" (Obj.repr 1))
    "last constant lost physical singleton identity";
  require (constants != repeated) "enum queries shared their mutable result array";
  require (HxArray.get constants 0 == HxArray.get repeated 0) "repeat query reboxed a singleton";
  require (HxArray.get constants 0 != HxArray.get (HxType.allEnums (HxType.enum_ "observer.Other")) 0)
    "different enum types shared a singleton box";
  let left = HxEnum.box_if_needed "observer.Equality" (Obj.repr (Payload 7)) in
  let right = HxEnum.box_if_needed "observer.Equality" (Obj.repr (Payload 7)) in
  require (left != right && HxType.enumEq left right) "equal payloads required the same box";
  require (not (HxType.enumEq left (HxEnum.box_if_needed "observer.Foreign" (Obj.repr (Payload 7)))))
    "equal native tags erased enum identity";
  require (not (HxType.enumEq left (Obj.repr (Payload 7)))) "unboxed data forged a named enum";
  require (HxEnum.enum_eq (Obj.repr (Payload 7)) (Obj.repr (Payload 7)))
    "existing raw variant equality changed";
  require (not (HxEnum.enum_eq (Obj.repr Atom) (Obj.repr (Payload 7))))
    "raw variant equality confused constants and payloads";
  let child = HxType.class_ "observer.Child" in
  let parent = HxType.class_ "observer.Base" in
  HxType.register_class_tags "observer.Child"
    ["observer.Child"; "observer.Base"; "observer.Named"];
  let value = HxAnon.create_with_class child in
  require (HxType.getClass value == child) "lost class descriptor";
  require (HxArray.length (HxAnon.fields value) = 0) "descriptor became public";
  require (HxType.isOfType value parent) "lost inherited runtime tag";

  HxAnon.set value "__hx_type" parent;
  require (HxType.getClass value == child) "public field replaced class identity";
  require (HxAnon.delete value "__hx_type") "public field deletion failed";
  require (HxType.getClass value == child) "public deletion erased class identity";
  let anonymous = HxAnon.create () in
  HxAnon.set anonymous "__hx_type" child;
  require (no_class anonymous) "public field forged class identity";
  require (no_class (HxAnon.copy value)) "field copy forged a class instance";
  require (no_class (HxAnon.create_with_class (Obj.repr "invalid")))
    "invalid descriptor became a class";
  require (no_class (HxAnon.create_with_class (HxType.enum_ "observer.Enum")))
    "enum descriptor became a class";
  let record = { __hx_type = child; value = 7 } in
  require (HxType.getClass (Obj.repr record) == child) "native record lost identity";

  let weak = Weak.create 1 in
  install_dead weak child;
  Gc.full_major ();
  Gc.compact ();
  require (Weak.get weak 0 = None) "runtime retained an unreachable instance";
  require (HxType.getClass value == child) "collection lost a live descriptor";
  require (HxType.isOfType value parent) "collection lost inherited tags";
  require (HxType.getClass (Obj.repr record) == child) "collection lost record identity";
  print_endline "NOMINAL_CARRIER_RUNTIME:PASS"
