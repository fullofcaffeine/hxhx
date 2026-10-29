(* Checked native method storage for compiler-selected record representations.

   Haxe owns declaration matching, overrides, signatures, record size, and each
   binder's typed receiver recovery. This module only installs immutable entries
   and checks their class/contract identity before invoking a binder. Contract
   keys and revisions are opaque: this code never parses a Haxe signature.

   The table stores class binders, not instances. A returned closure retains its
   original receiver through ordinary OCaml GC. Registration precedes generated
   allocation effects and does not depend on the reflection initialization hook.
   The native boundary is needed for heterogeneous, compiler-proven OCaml
   closures and private record descriptors; it owns no compiler policy. *)

type class_entries = {
  descriptor : Obj.t;
  revision : string;
  record_size : int;
  methods : (string, Obj.t -> Obj.t) Hashtbl.t;
}

let classes : (string, class_entries) Hashtbl.t = Hashtbl.create 31
let lock = Mutex.create ()

let fail message = invalid_arg ("HxMethodDispatch: " ^ message)

let synchronized action =
  Mutex.lock lock;
  Fun.protect action ~finally:(fun () -> Mutex.unlock lock)

let descriptor_name descriptor =
  if not (HxType.is_type_value HxType.class_marker descriptor) then
    fail "invalid class descriptor";
  HxType.getClassName descriptor

(* The generated factory contains only typed binders and contract constants.
   It must not call user code or recursively register another class. Building
   under the lock makes concurrent first allocations publish one complete set.
   Failure leaves the table unchanged. Repeated allocations do not rebuild it.
   Each allocation presents a fresh header; only its shared class descriptor
   remains in the registry, so distinct instances reuse the same entries. *)
let ensure header revision record_size make_entries =
  let descriptor = HxRuntime.identity_payload header in
  let name = descriptor_name descriptor in
  if revision = "" || record_size < 1 then fail "invalid class layout contract";
  synchronized (fun () ->
      match Hashtbl.find_opt classes name with
      | Some existing ->
          if existing.descriptor != descriptor || existing.revision <> revision
             || existing.record_size <> record_size then
            fail ("conflicting class layout: " ^ name)
      | None ->
          let entries = make_entries () in
          let methods = Hashtbl.create (Stdlib.List.length entries) in
          Stdlib.List.iter
            (fun (key, binder) ->
              if key = "" || Hashtbl.mem methods key then
                fail ("invalid or duplicate method contract: " ^ name);
              Hashtbl.add methods key binder)
            entries;
          Hashtbl.add classes name { descriptor; revision; record_size; methods })

let require_closure value =
  if Obj.is_int value
     || (Obj.tag value <> Obj.closure_tag && Obj.tag value <> Obj.infix_tag) then
    fail "method value is not an OCaml closure";
  value

(* Only the selected native record carrier may reach a concrete binder.
   Class-backed HxAnon objects are deliberately rejected: sharing a class name
   does not make their table storage a concrete OCaml record layout. *)
let bind receiver key =
  if HxRuntime.is_null receiver || Obj.is_int receiver || HxAnon.is_anon receiver
     || Obj.tag receiver <> 0 then
    fail "receiver is not a native class record";
  let descriptor = HxType.getClass receiver in
  let name = descriptor_name descriptor in
  let binder = synchronized (fun () ->
      match Hashtbl.find_opt classes name with
      | None -> fail ("class has no method entries: " ^ name)
      | Some entries ->
          if descriptor != entries.descriptor || Obj.size receiver <> entries.record_size then
            fail ("receiver layout differs from registered class: " ^ name);
          match Hashtbl.find_opt entries.methods key with
          | None -> fail ("class lacks method contract: " ^ name)
          | Some binder -> binder)
  in
  (* Invoke outside the table lock. The generated binder only recovers its
     checked record and creates the typed method closure. *)
  require_closure (binder receiver)

(* Haxe proves the anonymous field's ordinary closure representation. This
   primitive selects only the physical storage, and rejects absent/non-callable
   fields before generated syntax recovers the selected function type. *)
let bind_structural receiver field key =
  if HxAnon.is_anon receiver then (
    if not (HxRuntime.is_null (HxAnon.class_value receiver)) then
      fail "class-backed anonymous carrier needs its own dispatch contract";
    if not (HxAnon.has receiver field) then fail ("missing anonymous method: " ^ field);
    require_closure (HxAnon.get receiver field))
  else
    bind receiver key
