let contains (text : string) (needle : string) : bool =
  let text_length = String.length text in
  let needle_length = String.length needle in
  let rec loop index =
    if needle_length = 0 then true
    else if index + needle_length > text_length then false
    else if String.sub text index needle_length = needle then true
    else loop (index + 1)
  in
  loop 0

let require_contains (label : string) (output : string) (needle : string) : unit =
  if not (contains output needle) then
    failwith (label ^ ": missing `" ^ needle ^ "` in native parser output:\n" ^ output)

let () =
  let variant = if Array.length Sys.argv > 1 then Sys.argv.(1) else "unknown" in
  let source =
    String.concat "\n"
      [
        "package app;";
        "import model.Api;";
        "import model.Api.answer;";
        "import model.Api as Service;";
        "import model.Legacy in OldService;";
        "import model.Tools.*;";
        "using model.Extensions;";
        "class Main {}";
      ]
  in
  let output = HxHxNativeParser.parse_module_decl_with_expected source "Main" in
  require_contains "protocol version" output "hxhx_frontend_v=3";
  require_contains "normal import" output "import-normal\\nmodel.Api\\n";
  require_contains "static member import" output "import-normal\\nmodel.Api.answer\\n";
  require_contains "current alias spelling" output "import-alias\\nmodel.Api\\nService";
  require_contains "legacy alias spelling" output "import-alias\\nmodel.Legacy\\nOldService";
  require_contains "wildcard import" output "import-all\\nmodel.Tools\\n";
  require_contains "using directive" output "using\\nmodel.Extensions\\n";
  if not (contains output "\nok") then failwith ("native parser did not finish successfully:\n" ^ output);
  Printf.printf "NATIVE_PARSER_MODULE_DIRECTIVES:PASS variant=%s\n" variant
