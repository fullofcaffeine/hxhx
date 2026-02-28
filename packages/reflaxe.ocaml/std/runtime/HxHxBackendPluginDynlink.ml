(* HXHX Stage3 native backend plugin Dynlink bridge.

   Why
   - Stage3 plugin manifests may declare `backend.kind = "ocaml-dynlink"`.
   - Loading this kind is an OCaml runtime responsibility (`Dynlink.loadfile`) and must
     remain isolated behind one explicit boundary module.

   Contract
   - [load_and_capture manifest_path entry_path plugin_id]:
       1) resolves relative entry paths against the manifest directory,
       2) clears `HxHxBackendPluginHost` registration state,
       3) loads plugin artifact via Dynlink,
       4) returns encoded registration snapshot.
*)

let normalize_token ~(field : string) (value : string) : string =
  let token = String.trim value in
  if token = "" then
    invalid_arg ("HxHxBackendPluginDynlink." ^ field ^ " is required");
  token

let resolve_entry_path (manifest_path : string) (entry_path : string) : string =
  if Filename.is_implicit entry_path then
    Filename.concat (Filename.dirname manifest_path) entry_path
  else entry_path

let load_and_capture (manifest_path : string) (entry_path : string)
    (plugin_id : string) : string =
  let manifest_path = normalize_token ~field:"manifest_path" manifest_path in
  let entry_path = normalize_token ~field:"entry_path" entry_path in
  let plugin_id = normalize_token ~field:"plugin_id" plugin_id in
  let resolved_entry = resolve_entry_path manifest_path entry_path in
  if not (Sys.file_exists resolved_entry) then
    failwith
      ("native plugin artifact not found: " ^ resolved_entry ^ " (manifest: "
     ^ manifest_path ^ ", plugin: " ^ plugin_id ^ ")");
  HxHxBackendPluginHost.clear ();
  (try Dynlink.loadfile resolved_entry
   with Dynlink.Error err ->
     failwith
       ("failed to load native plugin `" ^ resolved_entry ^ "`: "
      ^ Dynlink.error_message err));
  HxHxBackendPluginHost.snapshot ()

let load_and_capture_safe (manifest_path : string) (entry_path : string)
    (plugin_id : string) : string =
  try "ok\n" ^ load_and_capture manifest_path entry_path plugin_id
  with exn -> "err\n" ^ Printexc.to_string exn
