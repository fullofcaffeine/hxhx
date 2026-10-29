(* This observer supplies fixed native carriers independently of Haxe lowering.
   It checks representation primitives and map behavior, not compiler ownership
   or workload cost. Production Haxe selects the allocations and their payloads. *)
type managed = {
  __hx_type : Obj.t;
  mutable catalog : Obj.t;
  nested : int ref;
}
type empty = { __hx_type : Obj.t }
type opaque = { state : int ref; mutable payload : Obj.t }

let require condition message = if not condition then failwith message
let managed () : managed =
  { __hx_type = HxType.instance_marker "observer.Identity";
    catalog = HxRuntime.hx_null; nested = ref 0 }
let empty () : empty =
  { __hx_type = HxType.instance_marker "observer.Empty" }
let size map = HxArray.length (HxMap.keys_object map)

let () =
  let descriptor = HxType.class_ "observer.Identity" in
  let first = managed () and distinct = managed () in
  let first_key = Obj.repr first and distinct_key = Obj.repr distinct in
  require (first != distinct && first.__hx_type != distinct.__hx_type)
    "managed allocations shared identity";
  require (HxRuntime.is_identity_header first.__hx_type
           && HxRuntime.identity_payload first.__hx_type == descriptor
           && HxType.getClass first_key == descriptor) "managed header payload";
  let empty_first = empty () and empty_second = empty () in
  require (empty_first != empty_second
           && empty_first.__hx_type != empty_second.__hx_type
           && HxRuntime.is_identity_header empty_first.__hx_type)
    "empty allocations shared identity";

  let fake_header = Obj.repr (Obj.repr (ref 0), 0, descriptor) in
  List.iter (fun value ->
      require (not (HxRuntime.is_identity_header value)) "false header accepted";
      require (HxRuntime.identity_payload value == HxRuntime.hx_null) "false payload accepted")
    [HxRuntime.hx_null; Obj.repr 1; Obj.repr "text"; Obj.repr 1.0;
     Obj.repr (fun value -> value); descriptor; fake_header];
  let plain : empty = { __hx_type = descriptor } in
  require (HxRuntime.identity_hash (Obj.repr plain) = 0
           && HxType.getClass (Obj.repr plain) == HxRuntime.hx_null)
    "descriptor-only record claimed managed layout";

  let anon = HxAnon.create () in
  require (HxAnon.is_anon anon && HxRuntime.is_identity_header (Obj.field anon 0))
    "anonymous allocation lacked managed header";
  let raw = { state = ref 0; payload = HxRuntime.hx_null } in
  let raw_key = Obj.repr raw in
  let array = HxArray.create () in
  let array_key = Obj.repr array in
  let map = HxMap.create_object () in
  HxMap.set_object map first_key 17;
  HxMap.set_object map anon 23;
  HxMap.set_object map raw_key 31;
  HxMap.set_object map array_key 37;
  let first_hash = HxRuntime.identity_hash first_key in
  let anon_hash = HxRuntime.identity_hash anon in
  first.catalog <- Obj.repr (ref ["new catalog"]);
  first.nested := 29;
  HxAnon.set anon "field" (Obj.repr 7);
  ignore (HxAnon.get anon "field");
  raw.state := 41;
  raw.payload <- first_key;
  for value = 0 to 63 do ignore (HxArray.push array value) done;
  Gc.minor (); Gc.full_major (); Gc.compact ();
  require (HxRuntime.identity_hash first_key = first_hash
           && HxRuntime.identity_hash anon = anon_hash) "managed mutation changed hash";
  require (HxRuntime.identity_hash raw_key = 0 && HxRuntime.identity_hash array_key = 0)
    "opaque mutation changed fallback";
  require (HxMap.get_object map first_key = 17 && HxMap.get_object map anon = 23
           && HxMap.get_object map raw_key = 31 && HxMap.get_object map array_key = 37
           && size map = 4) "mixed map lost a mutated key";
  require (not (HxMap.exists_object map distinct_key)) "equal-shaped key became an alias";
  HxMap.set_object map distinct_key 43;
  require (size map = 5) "distinct key replaced an association";
  let copied = HxMap.copy_object map in
  HxMap.set_object map first_key 47;
  require (size map = 5 && HxMap.get_object map first_key = 47
           && HxMap.get_object copied first_key = 17) "copy or replacement changed identity";
  require (HxMap.remove_object copied raw_key && not (HxMap.remove_object copied raw_key)
           && HxMap.get_object map raw_key = 31) "copy/remove changed original associations";
  HxMap.clear_object copied;
  require (size copied = 0 && size map = 5) "clear changed the original map";

  (* Shared headers deliberately force a hash collision in this native control.
     Generated allocations must still supply one fresh header per instance. *)
  let collision : managed = { first with nested = ref 29 } in
  let collision_key = Obj.repr collision in
  require (collision != first && HxRuntime.identity_hash collision_key = first_hash)
    "collision control did not collide";
  HxMap.set_object map collision_key 53;
  require (size map = 6 && HxMap.get_object map first_key = 47
           && HxMap.get_object map collision_key = 53) "stamp replaced physical equality";

  let anon_copy = HxAnon.copy anon in
  require (anon_copy != anon && HxAnon.is_anon anon_copy
           && HxRuntime.is_identity_header (Obj.field anon_copy 0)
           && Obj.field anon_copy 0 != Obj.field anon 0
           && (Obj.obj (HxAnon.get anon_copy "field") : int) = 7)
    "anonymous copy lost fields or fresh identity";
  let backed = HxAnon.create_with_class descriptor in
  require (HxType.getClass backed == descriptor
           && HxType.getClass (HxAnon.copy backed) == HxRuntime.hx_null)
    "anonymous copy changed class-backing behavior";

  (* Ordinary lazy evaluation supplies a tag-changing opaque carrier without
     forging allocator headers or changing tags through unsafe native writes. *)
  let effects = ref 0 in
  let lazy_value = lazy (incr effects; "forced") in
  let lazy_key = Obj.repr lazy_value in
  let before_tag = Obj.tag lazy_key in
  let lazy_map = HxMap.create_object () in
  HxMap.set_object lazy_map lazy_key 59;
  ignore (Lazy.force lazy_value);
  require (!effects = 1 && Obj.tag lazy_key <> before_tag
           && HxRuntime.identity_hash lazy_key = 0 && HxMap.get_object lazy_map lazy_key = 59)
    "lazy tag mutation lost opaque key";

  let headers = Array.init 4 (fun _ -> Array.make 64 HxRuntime.hx_null) in
  let threads = List.init 4 (fun worker -> Thread.create (fun () ->
      for index = 0 to 63 do
        headers.(worker).(index) <- HxRuntime.identity_header HxRuntime.hx_null
      done) ()) in
  List.iter Thread.join threads;
  let all = Array.concat (Array.to_list headers) in
  Array.iteri (fun index header ->
      require (HxRuntime.is_identity_header header) "concurrent allocation lacked header";
      for previous = 0 to index - 1 do
        require (header != all.(previous)) "concurrent allocations shared header"
      done) all;
  print_endline "OBJECT_MAP_IDENTITY_RUNTIME:PASS"
