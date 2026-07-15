(*
   End-to-end protocol assertions for the repo-owned native Haxe parser.

   The runner links either the canonical runtime parser or the committed
   bootstrap snapshot, parses one original Haxe fixture, and checks the decoded
   protocol payloads. It deliberately stays independent of compiler-generated
   OCaml so source/snapshot drift is visible before a full bootstrap run.
*)

let fail label actual =
  Printf.eprintf "native parser constrained generic arity: %s (got %S)\n" label
    actual;
  exit 1

let assert_equal label expected actual =
  if actual <> expected then fail (label ^ ", expected " ^ expected) actual

let assert_true label actual = if not actual then fail label "false"

let starts_with text prefix =
  let text_len = String.length text in
  let prefix_len = String.length prefix in
  text_len >= prefix_len && String.sub text 0 prefix_len = prefix

let contains text needle =
  let text_len = String.length text in
  let needle_len = String.length needle in
  let rec loop index =
    if needle_len = 0 then true
    else if index + needle_len > text_len then false
    else if String.sub text index needle_len = needle then true
    else loop (index + 1)
  in
  loop 0

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let ast_payloads prefix encoded =
  encoded |> String.split_on_char '\n'
  |> List.filter_map (fun line ->
         if starts_with line prefix then
           let raw =
             String.sub line (String.length prefix)
               (String.length line - String.length prefix)
           in
           Some (HxHxNativeParser.parse_len_payload raw)
         else None)

let payload_name separator payload =
  match String.index_opt payload separator with
  | Some index -> String.sub payload 0 index
  | None -> payload

let find_named label separator name payloads =
  match List.find_opt (fun payload -> payload_name separator payload = name) payloads with
  | Some payload -> payload
  | None -> fail (label ^ " missing " ^ name) ""

let method_field label index payload =
  let fields = String.split_on_char '|' payload in
  match List.nth_opt fields index with
  | Some value -> value
  | None -> fail (label ^ " missing protocol field") payload

let protocol source expected_class =
  HxHxNativeParser.parse_module_decl_with_expected source expected_class

let check_generic_owner source =
  let encoded = protocol source "GenericArityOwner" in
  let methods = ast_payloads "ast method " encoded in
  let bodies = ast_payloads "ast method_body " encoded in
  let append = find_named "generic owner method" '|' "appendClone" methods in
  assert_equal "appendClone argument names" "seed,values" (method_field "appendClone" 3 append);
  assert_equal "appendClone argument types" "seed:A,values:B" (method_field "appendClone" 7 append);
  let append_body = find_named "generic owner body" '\n' "appendClone" bodies in
  assert_true "appendClone body should preserve values.push"
    (contains append_body "values.push(clone)");
  assert_true "appendClone body should preserve return values"
    (contains append_body "return values");
  let zero = find_named "generic owner zero method" '|' "zero" methods in
  assert_equal "zero argument names" "" (method_field "zero" 3 zero);
  ignore (find_named "generic owner zero body" '\n' "zero" bodies)

let check_constructor_siblings source =
  let zero_encoded = protocol source "ZeroCtorSibling" in
  let zero_methods = ast_payloads "ast method " zero_encoded in
  let zero_bodies = ast_payloads "ast method_body " zero_encoded in
  let zero_new = find_named "zero constructor" '|' "new" zero_methods in
  assert_equal "zero constructor argument names" "" (method_field "ZeroCtorSibling.new" 3 zero_new);
  ignore (find_named "zero constructor body" '\n' "new" zero_bodies);

  let arg_encoded = protocol source "ArgCtorSibling" in
  let arg_methods = ast_payloads "ast method " arg_encoded in
  let arg_bodies = ast_payloads "ast method_body " arg_encoded in
  let arg_new = find_named "argument constructor" '|' "new" arg_methods in
  assert_equal "argument constructor names" "value" (method_field "ArgCtorSibling.new" 3 arg_new);
  assert_equal "argument constructor types" "value:String" (method_field "ArgCtorSibling.new" 7 arg_new);
  ignore (find_named "argument constructor body" '\n' "new" arg_bodies)

let () =
  if Array.length Sys.argv <> 3 then (
    prerr_endline
      "usage: native-parser-constrained-generic-arity-test <fixture.hx> <variant>";
    exit 2);
  let source = read_file Sys.argv.(1) in
  check_generic_owner source;
  check_constructor_siblings source;
  Printf.printf
    "NATIVE_PARSER_CONSTRAINED_GENERIC_ARITY:PASS variant=%s generic_args=2 zero_args=0 sibling_args=1\n"
    Sys.argv.(2)
