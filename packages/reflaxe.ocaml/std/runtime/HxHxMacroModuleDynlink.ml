let normalize_token ~(field : string) (value : string) : string =
  let token = Stdlib.String.trim value in
  if token = "" then
    invalid_arg ("HxHxMacroModuleDynlink." ^ field ^ " is required");
  token

let resolve_module_path (module_path : string) : string =
  if Stdlib.Filename.is_implicit module_path then
    Stdlib.Filename.concat (Stdlib.Sys.getcwd ()) module_path
  else module_path

let load_and_capture (module_path : string) (plugin_id : string) : string =
  let module_path = normalize_token ~field:"module_path" module_path in
  let plugin_id = normalize_token ~field:"plugin_id" plugin_id in
  let resolved_module_path = resolve_module_path module_path in
  if not (Stdlib.Sys.file_exists resolved_module_path) then
    failwith
      ("native macro module artifact not found: " ^ resolved_module_path
     ^ " (plugin: " ^ plugin_id ^ ")");
  HxHxMacroModuleHost.clear ();
  (try Dynlink.loadfile resolved_module_path
   with Dynlink.Error err ->
     failwith
       ("failed to load native macro module `" ^ resolved_module_path ^ "`: "
      ^ Dynlink.error_message err));
  HxHxMacroModuleHost.snapshot ()

let load_and_capture_safe (module_path : string) (plugin_id : string) : string =
  try "ok\n" ^ load_and_capture module_path plugin_id
  with exn -> "err\n" ^ Printexc.to_string exn

(* Identity of the running compiler binary, read before a project-macro plugin is built or
   loaded. A plugin links against this binary's runtime units, so it must be built by the same
   OCaml version and must be rebuilt whenever the binary changes. Haxe owns every decision made
   from these two values (cache keys, receipts, diagnostics). *)
let host_ocaml_version () : string = Stdlib.Sys.ocaml_version

let host_executable_digest () : string =
  Stdlib.Digest.to_hex (Stdlib.Digest.file Stdlib.Sys.executable_name)

(* Process id of the compiler, recorded as the owner of a plugin build lock so that a lock left
   by an interrupted build can be recognized once its owner is gone. *)
let host_pid () : int = Unix.getpid ()
