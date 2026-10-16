(* Independent observations of private class storage and ordinary OCaml GC.
   Haxe selects names and ancestry in production; this observer supplies fixed
   descriptors solely to exercise the native representation boundary. *)
type native_record = { __hx_type : Obj.t; value : int }

let require condition message = if not condition then failwith message
let no_class value = HxRuntime.is_null (HxType.getClass value)

let[@inline never] install_dead weak descriptor =
  let value = HxAnon.create_with_class descriptor in
  Weak.set weak 0 (Some value)

let () =
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
