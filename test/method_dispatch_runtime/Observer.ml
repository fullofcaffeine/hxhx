(* Independent assertions for the native registry boundary. The production
   compiler, not this observer, must later prove the generated binders. *)
type counter = { marker : Obj.t; mutable value : int; padding : string }
type other = { marker : Obj.t; padding : string; mutable value : int; extra : bool }

let check condition message = if not condition then failwith message

let rejected action =
  try action (); false with Invalid_argument _ -> true

let () =
  let descriptor = HxType.class_ "Observer.Counter" in
  let builds = ref 0 in
  let make () =
    incr builds;
    ["add:int->int", (fun receiver ->
        let self : counter = Obj.obj receiver in
        Obj.repr (fun amount -> self.value <- self.value + amount; self.value));
     "read:unit->int", (fun receiver ->
        let self : counter = Obj.obj receiver in
        Obj.repr (fun () -> self.value))]
  in
  HxMethodDispatch.ensure descriptor "layout-a" 3 make;
  HxMethodDispatch.ensure descriptor "layout-a" 3 make;
  check (!builds = 1) "allocation rebuilt class binders";
  let instance : counter = { marker = descriptor; value = 10; padding = "padding" } in
  let receiver = Obj.repr instance in
  let add : int -> int = Obj.obj (HxMethodDispatch.bind receiver "add:int->int") in
  let read : unit -> int = Obj.obj (HxMethodDispatch.bind receiver "read:unit->int") in
  check (add 2 = 12 && read () = 12 && instance.value = 12) "bound receiver state";
  Gc.full_major (); Gc.compact ();
  check (add 3 = 15 && read () = 15) "bound receiver survived GC";

  let other_descriptor = HxType.class_ "Observer.Other" in
  HxMethodDispatch.ensure other_descriptor "layout-b" 4 (fun () ->
      ["read:unit->int", (fun receiver ->
          let self : other = Obj.obj receiver in
          Obj.repr (fun () -> self.value))]);
  let other_instance : other = { marker = other_descriptor; padding = "other"; value = 27; extra = true } in
  let other_read : unit -> int = Obj.obj (HxMethodDispatch.bind (Obj.repr other_instance) "read:unit->int") in
  check (other_read () = 27) "different concrete method layout";
  check (rejected (fun () -> ignore (HxMethodDispatch.bind receiver "read:unit->string"))) "signature mismatch accepted";
  check (rejected (fun () -> HxMethodDispatch.ensure descriptor "changed" 3 make)) "changed revision accepted";
  check (rejected (fun () -> HxMethodDispatch.ensure descriptor "layout-a" 4 make)) "changed size accepted";
  check (rejected (fun () -> ignore (HxMethodDispatch.bind HxRuntime.hx_null "read:unit->int"))) "null receiver accepted";
  check (rejected (fun () -> ignore (HxMethodDispatch.bind (Obj.repr 2) "read:unit->int"))) "integer receiver accepted";
  check (rejected (fun () -> ignore (HxMethodDispatch.bind (Obj.repr "text") "read:unit->int"))) "string receiver accepted";
  let wrong_size = Obj.repr (descriptor, 1) in
  check (rejected (fun () -> ignore (HxMethodDispatch.bind wrong_size "read:unit->int"))) "wrong record size accepted";
  let unregistered : counter = { marker = HxType.class_ "Observer.Unregistered"; value = 0; padding = "" } in
  check (rejected (fun () -> ignore (HxMethodDispatch.bind (Obj.repr unregistered) "read:unit->int"))) "unregistered class accepted";
  check (rejected (fun () -> HxMethodDispatch.ensure HxRuntime.hx_null "layout" 3 make)) "invalid descriptor accepted";

  let ordinary = HxAnon.create () in
  ignore (HxAnon.set ordinary "read" (Obj.repr (fun () -> 31)));
  let ordinary_read : unit -> int = Obj.obj (HxMethodDispatch.bind_structural ordinary "read" "read:unit->int") in
  check (ordinary_read () = 31) "ordinary anonymous method";
  let structural_read : unit -> int = Obj.obj (HxMethodDispatch.bind_structural receiver "read" "read:unit->int") in
  check (structural_read () = 15) "native structural method";
  check (rejected (fun () -> ignore (HxMethodDispatch.bind_structural ordinary "absent" "read:unit->int"))) "missing anonymous field accepted";
  ignore (HxAnon.set ordinary "read" (Obj.repr 42));
  check (rejected (fun () -> ignore (HxMethodDispatch.bind_structural ordinary "read" "read:unit->int"))) "non-callable anonymous field accepted";
  let class_backed = HxAnon.create_with_class descriptor in
  ignore (HxAnon.set class_backed "read" (Obj.repr (fun () -> 99)));
  check (rejected (fun () -> ignore (HxMethodDispatch.bind_structural class_backed "read" "read:unit->int"))) "class-backed table reached native binder";

  let failed_descriptor = HxType.class_ "Observer.Failed" in
  let binder _ = Obj.repr (fun () -> 8) in
  check (rejected (fun () -> HxMethodDispatch.ensure failed_descriptor "layout-f" 3
      (fun () -> ["same", binder; "same", binder]))) "duplicate contracts accepted";
  HxMethodDispatch.ensure failed_descriptor "layout-f" 3 (fun () -> ["valid", binder]);
  let failed_instance : counter = { marker = failed_descriptor; value = 0; padding = "" } in
  let recovered : unit -> int = Obj.obj (HxMethodDispatch.bind (Obj.repr failed_instance) "valid") in
  check (recovered () = 8) "failed registration published partial entries";
  let bad_descriptor = HxType.class_ "Observer.BadBinder" in
  HxMethodDispatch.ensure bad_descriptor "layout-bad" 3 (fun () -> ["bad", (fun _ -> Obj.repr 1)]);
  let bad_instance : counter = { marker = bad_descriptor; value = 0; padding = "" } in
  check (rejected (fun () -> ignore (HxMethodDispatch.bind (Obj.repr bad_instance) "bad"))) "non-callable binder result accepted";

  let concurrent_descriptor = HxType.class_ "Observer.Concurrent" in
  let concurrent_builds = ref 0 in
  let allocate () = HxMethodDispatch.ensure concurrent_descriptor "layout-c" 3 (fun () ->
      incr concurrent_builds; ["valid", binder]) in
  let threads = List.init 8 (fun _ -> Thread.create allocate ()) in
  List.iter Thread.join threads;
  check (!concurrent_builds = 1) "concurrent allocation rebuilt entries";
  print_endline "METHOD_DISPATCH_RUNTIME:PASS"
