let snapshot_version : string = "v2"
let abi_version : int = 1
let macro_api_version : int = 1

type expr_registration = {
  plugin_id : string;
  expr : string;
  run : unit -> string;
}

let registrations : expr_registration list ref = ref []

let normalize_token ~(field : string) (value : string) : string =
  let token = Stdlib.String.trim value in
  if token = "" then
    invalid_arg ("HxHxMacroModuleHost." ^ field ^ " is required");
  if String.contains token '\n' || String.contains token '\r' then
    invalid_arg
      ("HxHxMacroModuleHost." ^ field ^ " must not contain newline characters");
  if String.contains token '\t' then
    invalid_arg ("HxHxMacroModuleHost." ^ field ^ " must not contain tabs");
  token

let clear () : unit = registrations := []

let register_expr_handler (plugin_id : string) (expr : string)
    (run : unit -> string) : unit =
  let plugin_id = normalize_token ~field:"plugin_id" plugin_id in
  let expr = normalize_token ~field:"expr" expr in
  let duplicate =
    List.exists
      (fun row -> row.plugin_id = plugin_id && row.expr = expr)
      !registrations
  in
  if duplicate then
    invalid_arg
      ("HxHxMacroModuleHost.duplicate registration plugin_id=" ^ plugin_id
     ^ " expr=" ^ expr)
  else registrations := { plugin_id; expr; run } :: !registrations

let () =
  Callback.register "hxhx_macro_module_register_expr_handler"
    register_expr_handler

let snapshot () : string =
  let lines = Buffer.create 256 in
  Buffer.add_string lines snapshot_version;
  Buffer.add_char lines '\n';
  Buffer.add_string lines ("abiVersion=" ^ string_of_int abi_version);
  Buffer.add_char lines '\n';
  Buffer.add_string lines ("macroApiVersion=" ^ string_of_int macro_api_version);
  Buffer.add_char lines '\n';
  List.iter
    (fun row ->
      Buffer.add_string lines row.plugin_id;
      Buffer.add_char lines '\t';
      Buffer.add_string lines row.expr;
      Buffer.add_char lines '\n')
    (List.rev !registrations);
  Buffer.contents lines

let run_expr (expr : string) : string =
  let normalized = normalize_token ~field:"expr" expr in
  let rec loop (rows : expr_registration list) : string =
    match rows with
    | [] ->
        failwith ("native macro expr not registered: " ^ normalized)
    | row :: rest ->
        if row.expr = normalized then row.run () else loop rest
  in
  loop !registrations
