let normalize_token ~(field : string) (value : string) : string =
  let token = String.trim value in
  if token = "" then
    invalid_arg ("HxHxMacroModuleDynlink." ^ field ^ " is required");
  token

let resolve_module_path (module_path : string) : string =
  if Filename.is_implicit module_path then
    Filename.concat (Sys.getcwd ()) module_path
  else module_path

let load_and_capture (module_path : string) (plugin_id : string) : string =
  let module_path = normalize_token ~field:"module_path" module_path in
  let plugin_id = normalize_token ~field:"plugin_id" plugin_id in
  let resolved_module_path = resolve_module_path module_path in
  if not (Sys.file_exists resolved_module_path) then
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
