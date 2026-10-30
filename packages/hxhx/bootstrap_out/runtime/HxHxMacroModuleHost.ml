(* Registration table for project-macro plugins.

   A plugin registers one callback per macro declaration while it is being
   loaded. The callback receives an encoded argument payload and returns an
   encoded result payload; both are produced and read by the Haxe-authored
   [hxhxmacrohost.MacroSyntaxWire]. This module only stores callbacks, lists
   them for validation, and calls the one the compiler selected. It never
   reads the payloads or decides what a macro means. *)

let snapshot_version : string = "v3"
let abi_version : int = 2
let macro_api_version : int = 1

type declaration_registration = {
  plugin_id : string;
  declaration : string;
  run : string -> string;
}

let registrations : declaration_registration list ref = ref []

let normalize_token ~(field : string) (value : string) : string =
  let token = Stdlib.String.trim value in
  if token = "" then
    invalid_arg ("HxHxMacroModuleHost." ^ field ^ " is required");
  if Stdlib.String.contains token '\n' || Stdlib.String.contains token '\r' then
    invalid_arg
      ("HxHxMacroModuleHost." ^ field ^ " must not contain newline characters");
  if Stdlib.String.contains token '\t' then
    invalid_arg ("HxHxMacroModuleHost." ^ field ^ " must not contain tabs");
  token

let clear () : unit = registrations := []

let register_macro_declaration (plugin_id : string) (declaration : string)
    (run : string -> string) : unit =
  let plugin_id = normalize_token ~field:"plugin_id" plugin_id in
  let declaration = normalize_token ~field:"declaration" declaration in
  let duplicate =
    Stdlib.List.exists
      (fun row -> row.plugin_id = plugin_id && row.declaration = declaration)
      !registrations
  in
  if duplicate then
    invalid_arg
      ("HxHxMacroModuleHost.duplicate registration plugin_id=" ^ plugin_id
     ^ " declaration=" ^ declaration)
  else registrations := { plugin_id; declaration; run } :: !registrations

let () =
  Callback.register "hxhx_macro_module_register_macro_declaration"
    register_macro_declaration

let snapshot () : string =
  let lines = Buffer.create 256 in
  Buffer.add_string lines snapshot_version;
  Buffer.add_char lines '\n';
  Buffer.add_string lines ("abiVersion=" ^ string_of_int abi_version);
  Buffer.add_char lines '\n';
  Buffer.add_string lines ("macroApiVersion=" ^ string_of_int macro_api_version);
  Buffer.add_char lines '\n';
  Stdlib.List.iter
    (fun row ->
      Buffer.add_string lines row.plugin_id;
      Buffer.add_char lines '\t';
      Buffer.add_string lines row.declaration;
      Buffer.add_char lines '\n')
    (Stdlib.List.rev !registrations);
  Buffer.contents lines

(* Returns "ok\n" ^ payload, or "err\n" ^ message when the declaration is not
   registered or its callback raised an OCaml exception. The Haxe caller turns
   an error into a compile error at the macro call. *)
let run_declaration (declaration : string) (payload : string) : string =
  try
    let normalized = normalize_token ~field:"declaration" declaration in
    let rec loop (rows : declaration_registration list) : string =
      match rows with
      | [] -> failwith ("native macro declaration not registered: " ^ normalized)
      | row :: rest ->
          if row.declaration = normalized then row.run payload else loop rest
    in
    "ok\n" ^ loop !registrations
  with exn -> "err\n" ^ Printexc.to_string exn
