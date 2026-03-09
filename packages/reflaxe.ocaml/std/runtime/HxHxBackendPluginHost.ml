(* HXHX Stage3 native backend plugin host registry bridge.

   Why
   - Native `.cmxs` backend plugins need a tiny deterministic side-effect API to register
     provider type names while they are loaded via Dynlink.
   - Haxe side keeps typed validation in `hxhx.NativeBackendPluginHostAbi`; this module
     only stores and serializes raw registration rows.

   Snapshot wire format
   - First line:  "v1"
   - Remaining lines: "<pluginId>\t<providerType>"
*)

let snapshot_version : string = "v1"

type provider_registration = {
  plugin_id : string;
  provider_type : string;
}

let registrations : provider_registration list ref = ref []

let normalize_token ~(field : string) (value : string) : string =
  let token = Stdlib.String.trim value in
  if token = "" then
    invalid_arg ("HxHxBackendPluginHost." ^ field ^ " is required");
  if String.contains token '\n' || String.contains token '\r' then
    invalid_arg
      ("HxHxBackendPluginHost." ^ field ^ " must not contain newline characters");
  if String.contains token '\t' then
    invalid_arg ("HxHxBackendPluginHost." ^ field ^ " must not contain tabs");
  token

let clear () : unit = registrations := []

let register_provider_type (plugin_id : string) (provider_type : string) : unit =
  let plugin_id = normalize_token ~field:"plugin_id" plugin_id in
  let provider_type = normalize_token ~field:"provider_type" provider_type in
  let duplicate =
    List.exists
      (fun row -> row.plugin_id = plugin_id && row.provider_type = provider_type)
      !registrations
  in
  if duplicate then
    invalid_arg
      ("HxHxBackendPluginHost.duplicate registration plugin_id=" ^ plugin_id
      ^ " provider_type=" ^ provider_type)
  else
    registrations := { plugin_id; provider_type } :: !registrations

let () =
  Callback.register "hxhx_backend_plugin_register_provider_type"
    register_provider_type

let snapshot () : string =
  let lines = Buffer.create 256 in
  Buffer.add_string lines snapshot_version;
  Buffer.add_char lines '\n';
  List.iter
    (fun row ->
      Buffer.add_string lines row.plugin_id;
      Buffer.add_char lines '\t';
      Buffer.add_string lines row.provider_type;
      Buffer.add_char lines '\n')
    (List.rev !registrations);
  Buffer.contents lines
