#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/hxhx/finalize-bootstrap-dir.sh <bootstrap-dir>

Why:
  Finalize a hydrated bootstrap/source emit directory into the exact generated OCaml
  shape expected by the committed bootstrap snapshot.

What:
  - Applies the existing bootstrap repair sequence to a target directory.
  - Rehydrates shard manifests first when needed.
  - Does not run dune and does not re-shard the directory.
USAGE
}

if [ "$#" -ne 1 ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  [ "$#" -eq 1 ] && [ "${1:-}" != "-h" ] && [ "${1:-}" != "--help" ] && exit 1
  exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOTSTRAP_PATCH_HELPER="$ROOT/scripts/hxhx/bootstrap_patch_helper.py"
BOOTSTRAP_PATCH_PAYLOAD_DIR="$ROOT/scripts/hxhx/bootstrap_patch_payloads"

run_bootstrap_patch_helper() {
  python3 "$BOOTSTRAP_PATCH_HELPER" "$@"
}

insert_bootstrap_patch_before_anchor() {
  local target_path="$1"
  local temp_path="$2"
  local anchor="$3"
  local payload_path="$4"
  local error_message="$5"

  run_bootstrap_patch_helper     insert-before-anchor     "$target_path"     "$temp_path"     "$anchor"     "$payload_path"     "$error_message"
}

file_contains_literal() {
  local needle="$1"
  local path="$2"

  if command -v rg >/dev/null 2>&1; then
    rg -Fq "$needle" "$path"
  else
    grep -Fq -- "$needle" "$path"
  fi
}

patch_bootstrap_emitter_root_sys_stdio() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"
  local anchor='ignore (let shimName = ("Haxe_macro_Context" : string)'
  local marker='(* hxhx(stage3) bootstrap shim: root Sys stdio repair *)'
  local temp_path="$emitter_path.tmp"
  local payload_path="$BOOTSTRAP_PATCH_PAYLOAD_DIR/root_sys_stdio.mlpatch"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal "$marker" "$emitter_path"; then
    return 0
  fi

  insert_bootstrap_patch_before_anchor     "$emitter_path"     "$temp_path"     "$anchor"     "$payload_path"     "build-hxhx: failed to locate root Sys stdio repair anchor in EmitterStage.ml"

  mv "$temp_path" "$emitter_path"
}

patch_bootstrap_emitter_project_generator_helper_calls() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"
  local anchor='ignore (let shimName = ("Haxe_macro_Context" : string)'
  local marker='(* hxhx(stage3) bootstrap shim: ProjectGenerator helper-call repair *)'
  local temp_path="$emitter_path.project_generator_helpers.tmp"
  local payload_path="$BOOTSTRAP_PATCH_PAYLOAD_DIR/project_generator_helper_calls.mlpatch"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal "$marker" "$emitter_path"; then
    return 0
  fi

  insert_bootstrap_patch_before_anchor     "$emitter_path"     "$temp_path"     "$anchor"     "$payload_path"     "build-hxhx: failed to locate ProjectGenerator helper repair anchor in EmitterStage.ml"

  mv "$temp_path" "$emitter_path"
}

patch_bootstrap_emitter_load_template_fallback() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"
  local anchor='ignore (let shimName = ("Haxe_macro_Context" : string)'
  local marker='(* hxhx(stage3) bootstrap shim: loadTemplate fallback repair *)'
  local temp_path="$emitter_path.load_template.tmp"
  local payload_path="$BOOTSTRAP_PATCH_PAYLOAD_DIR/load_template_fallback.mlpatch"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal "$marker" "$emitter_path"; then
    return 0
  fi

  insert_bootstrap_patch_before_anchor     "$emitter_path"     "$temp_path"     "$anchor"     "$payload_path"     "build-hxhx: failed to locate loadTemplate fallback repair anchor in EmitterStage.ml"

  mv "$temp_path" "$emitter_path"
}

patch_bootstrap_emitter_template_engine_condition() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"
  local anchor='ignore (let shimName = ("Haxe_macro_Context" : string)'
  local marker='(* hxhx(stage3) bootstrap shim: TemplateEngine.evaluateCondition repair *)'
  local temp_path="$emitter_path.template_engine.tmp"
  local payload_path="$BOOTSTRAP_PATCH_PAYLOAD_DIR/template_engine_condition.mlpatch"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal "$marker" "$emitter_path"; then
    return 0
  fi

  insert_bootstrap_patch_before_anchor     "$emitter_path"     "$temp_path"     "$anchor"     "$payload_path"     "build-hxhx: failed to locate TemplateEngine repair anchor in EmitterStage.ml"

  mv "$temp_path" "$emitter_path"
}

patch_bootstrap_emitter_php_syntax_empty_rest_calls() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"
  local anchor='ignore (let shimName = ("Haxe_macro_Context" : string)'
  local marker='(* hxhx(stage3) bootstrap shim: Php_Syntax empty-rest repair *)'
  local temp_path="$emitter_path.php_syntax.tmp"
  local payload_path="$BOOTSTRAP_PATCH_PAYLOAD_DIR/php_syntax_empty_rest_calls.mlpatch"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal "$marker" "$emitter_path"; then
    return 0
  fi

  insert_bootstrap_patch_before_anchor     "$emitter_path"     "$temp_path"     "$anchor"     "$payload_path"     "build-hxhx: failed to locate Php_Syntax empty-rest repair anchor in EmitterStage.ml"

  mv "$temp_path" "$emitter_path"
}

patch_bootstrap_emitter_php_boot_float_zero_compare() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"
  local anchor='ignore (let shimName = ("Haxe_macro_Context" : string)'
  local marker='(* hxhx(stage3) bootstrap shim: Php_Boot float zero compare repair *)'
  local temp_path="$emitter_path.php_boot_float_zero.tmp"
  local payload_path="$BOOTSTRAP_PATCH_PAYLOAD_DIR/php_boot_float_zero_compare.mlpatch"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal "$marker" "$emitter_path"; then
    return 0
  fi

  insert_bootstrap_patch_before_anchor \
    "$emitter_path" \
    "$temp_path" \
    "$anchor" \
    "$payload_path" \
    "build-hxhx: failed to locate Php_Boot float-zero repair anchor in EmitterStage.ml"

  mv "$temp_path" "$emitter_path"
}

patch_bootstrap_emitter_php_boot_string_key_lookups() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"
  local anchor='ignore (let shimName = ("Haxe_macro_Context" : string)'
  local marker='(* hxhx(stage3) bootstrap shim: Php_Boot string-key lookup repair *)'
  local temp_path="$emitter_path.php_boot_string_keys.tmp"
  local payload_path="$BOOTSTRAP_PATCH_PAYLOAD_DIR/php_boot_string_key_lookups.mlpatch"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal "$marker" "$emitter_path"; then
    return 0
  fi

  insert_bootstrap_patch_before_anchor \
    "$emitter_path" \
    "$temp_path" \
    "$anchor" \
    "$payload_path" \
    "build-hxhx: failed to locate Php_Boot string-key repair anchor in EmitterStage.ml"

  mv "$temp_path" "$emitter_path"
}

patch_bootstrap_emitter_haxe_io_eof_presence() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"
  local anchor='ignore (let shimName = ("Haxe_macro_Context" : string)'
  local marker='(* hxhx(stage3) bootstrap shim: haxe.io.Eof presence repair *)'
  local temp_path="$emitter_path.haxe_io_eof_presence.tmp"
  local payload_path="$BOOTSTRAP_PATCH_PAYLOAD_DIR/haxe_io_eof_presence.mlpatch"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal "$marker" "$emitter_path"; then
    return 0
  fi

  insert_bootstrap_patch_before_anchor \
    "$emitter_path" \
    "$temp_path" \
    "$anchor" \
    "$payload_path" \
    "build-hxhx: failed to locate haxe.io.Eof presence repair anchor in EmitterStage.ml"

  mv "$temp_path" "$emitter_path"
}

patch_bootstrap_emitter_array_receiver_chain_lowering() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"
  local marker='(* hxhx(stage3) bootstrap shim: array receiver chain lowering repair *)'

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal "$marker" "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-array-receiver-chain-lowering "$emitter_path"
}

patch_bootstrap_emitter_type_create_instance() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"
  local anchor='                              | "getClass" -> if HxArray.length _g1 = 1 then let _g5 = Obj.magic (HxArray.get (Obj.magic _g1) 0) in ('
  local marker='(* hxhx(stage3) bootstrap shim: Type.createInstance class resolution repair *)'
  local temp_path="$emitter_path.type_create_instance.tmp"
  local payload_path="$BOOTSTRAP_PATCH_PAYLOAD_DIR/type_create_instance.mlpatch"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal "$marker" "$emitter_path"; then
    return 0
  fi

  insert_bootstrap_patch_before_anchor \
    "$emitter_path" \
    "$temp_path" \
    "$anchor" \
    "$payload_path" \
    "build-hxhx: failed to locate Type.createInstance repair anchor in EmitterStage.ml"

  mv "$temp_path" "$emitter_path"
}

patch_bootstrap_hxparser_interpolated_exprs() {
  local build_dir="$1"
  local parser_path="$build_dir/HxParser.ml"
  local marker='(* hxhx(stage3) bootstrap shim: HxParser interpolation expr repair *)'

  if [ ! -f "$parser_path" ]; then
    return 0
  fi

  if file_contains_literal "$marker" "$parser_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-hxparser-interpolated-exprs "$parser_path"
}

patch_bootstrap_hxparser_generic_function_decl() {
  local build_dir="$1"
  local parser_path="$build_dir/HxParser.ml"

  if [ ! -f "$parser_path" ]; then
    return 0
  fi

  if file_contains_literal '__enum_param_90001' "$parser_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-hxparser-generic-function-decl "$parser_path"
}

patch_bootstrap_hxparser_uppercase_helper_call() {
  local build_dir="$1"
  local parser_path="$build_dir/HxParser.ml"

  if [ ! -f "$parser_path" ]; then
    return 0
  fi

  if file_contains_literal 'hasLowerAlpha (name : string) && HxString.indexOf name "_" 0 = -1' "$parser_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-hxparser-uppercase-helper-call "$parser_path"
}

patch_bootstrap_native_parser_generic_arrow_constraints() {
  local build_dir="$1"
  local parser_path="$build_dir/runtime/HxHxNativeParser.ml"

  if [ ! -f "$parser_path" ]; then
    return 0
  fi

  if file_contains_literal "Function type arrows inside generic constraints" "$parser_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-native-parser-generic-arrow-constraints "$parser_path"
}

patch_bootstrap_native_parser_expr_spacing() {
  local build_dir="$1"
  local parser_path="$build_dir/runtime/HxHxNativeParser.ml"

  if [ ! -f "$parser_path" ]; then
    return 0
  fi

  if file_contains_literal 'let append_token_text (b : Buffer.t) (text : string) : unit =' "$parser_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-native-parser-expr-spacing "$parser_path"
}

patch_bootstrap_emitter_typed_param_fallback() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'bootstrap shim: typed param fallback for emitted fn args' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-emitter-typed-param-fallback "$emitter_path"
}

patch_bootstrap_emitter_parsed_arg_type_overlay() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'bootstrap shim: parsed arg type overlay for tyByIdent' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-emitter-parsed-arg-type-overlay "$emitter_path"
}

patch_bootstrap_emitter_preapplied_sig_fallback() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if ! file_contains_literal '&& not (receiverPreApplied)' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-emitter-preapplied-sig-fallback "$emitter_path"
}

patch_bootstrap_stage1_std_root_termination() {
  local build_dir="$1"
  local stage1_path="$build_dir/hxhx_Stage1Compiler.ml"

  if [ ! -f "$stage1_path" ]; then
    return 0
  fi

  if file_contains_literal 'StringTools.startsWith (nextDir : string) ("../" : string)' "$stage1_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-stage1-std-root-termination "$stage1_path"
}

patch_bootstrap_emitter_allowed_ident_fallback() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'let currentAllowedValueIdentNames = ref (Obj.magic (HxRuntime.hx_null) : bool HxMap.string_map)' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-allowed-ident-fallback "$emitter_path"
}

patch_bootstrap_emitter_stmt_local_allowed_idents() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'let stmtToUnit = ref (Obj.magic (HxRuntime.hx_null) : HxStmt.hxstmt -> TyType.t HxMap.string_map -> bool HxMap.string_map -> string) in (' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-stmt-local-allowed-idents "$emitter_path"
}

patch_bootstrap_emitter_typed_ty_map_copying() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'let typedTy = Obj.magic ty in let keys = if typedTy == Obj.magic (HxRuntime.hx_null) then Obj.magic (HxRuntime.hx_null) else HxMap.keys_string typedTy in (' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-typed-ty-map-copying "$emitter_path"
}

patch_bootstrap_emitter_typed_map_helper_obj_repr() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'bootstrap shim: typed-map Obj.repr helper repair' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-typed-map-helper-obj-repr "$emitter_path"
}

patch_bootstrap_emitter_nested_call_arg_reprs() {
  local build_dir="$1"
  local emitter_path=""
  local shard_extend_ty_literal='extendTyByIdentMany (Obj.repr tyByIdent)'
  local patched_shard=0

  for emitter_path in "$build_dir"/EmitterStage.ml.part*; do
    if [ ! -f "$emitter_path" ]; then
      continue
    fi
    if ! file_contains_literal "$shard_extend_ty_literal" "$emitter_path"; then
      continue
    fi
    run_bootstrap_patch_helper patch-nested-emitter-call-arg-reprs "$emitter_path"
    patched_shard=1
  done

  if [ "$patched_shard" = "1" ] && [ -f "$build_dir/EmitterStage.ml.parts" ]; then
    bash "$ROOT/scripts/hxhx/hydrate-bootstrap-shards.sh" "$build_dir" >&2
  fi

  emitter_path="$build_dir/EmitterStage.ml"
  if [ -f "$emitter_path" ] && [ "$patched_shard" != "1" ]; then
    run_bootstrap_patch_helper patch-fast-emitter-nested-literals "$emitter_path"
  fi

  if [ ! -f "$build_dir/EmitterStage.ml" ] && ! compgen -G "$build_dir/EmitterStage.ml.part*" >/dev/null; then
    return 0
  fi
}

patch_bootstrap_emitter_module_name_lookup_raw_map() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'moduleNameByPkgAndClassRaw' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-module-name-lookup-raw-map "$emitter_path"
}

patch_bootstrap_emitter_typed_ty_ident_lookups() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'let getTyIdentRaw = fun name -> let typedTyByIdent = Obj.magic tyByIdent' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-typed-ty-ident-lookups "$emitter_path"
}

patch_bootstrap_emitter_return_expr_ty_ident_lookups() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'bootstrap shim: returnExprToOcaml ty lookup repair' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-typed-ty-ident-lookups "$emitter_path"
}

patch_bootstrap_emitter_expr_ident_ty_reads() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'bootstrap shim: exprToOcaml ident read repair' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-typed-ty-ident-lookups "$emitter_path"
}

patch_bootstrap_emitter_negative_unop_is_int_expr() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal '| HxExpr.EUnop (_p0, _p1) -> let _g = (_p0 : string) in let _g1 = Obj.magic _p1 in if HxString.equals _g "-" then let inner = Obj.magic _g1 in let __assign_246a = (!isIntExpr) (Obj.magic inner)' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-negative-unop-is-int-expr "$emitter_path"
}

patch_bootstrap_emitter_instance_call_receiver_forwarding() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'bootstrap shim: instance call receiver forwarding repair' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-instance-call-receiver-forwarding "$emitter_path"
}

patch_bootstrap_emitter_instance_call_this_binding() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'bootstrap shim: instance call this-binding repair' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-instance-call-this-binding "$emitter_path"
}

patch_bootstrap_emitter_instance_method_value_binding() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'hasCurrentInstanceMethod (name : string) && (mapGetRaw (Obj.repr tyByIdent) (!tempString3 : string) != Obj.magic (HxRuntime.hx_null) || mapGetRaw (Obj.repr tyByIdent) (!tempString4 : string) != Obj.magic (HxRuntime.hx_null) || hasAllowedValueIdent ("this" : string) || hasAllowedValueIdent ("this_" : string))' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-instance-method-value-binding "$emitter_path"
}

patch_bootstrap_emitter_instance_call_preapplied_arity() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'bootstrap shim: preapplied receiver arity repair' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-instance-call-preapplied-arity "$emitter_path"
}

patch_bootstrap_emitter_string_length_fallback() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'bootstrap shim: string length fallback repair' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-string-length-fallback "$emitter_path"
}

patch_bootstrap_emitter_string_length_stdlib() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'bootstrap shim: string length stdlib repair' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-string-length-stdlib "$emitter_path"
}

patch_bootstrap_emitter_mutable_local_string_init_hints() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'bootstrap shim: mutable-local string init hint repair' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-mutable-local-string-init-hints "$emitter_path"
}

patch_bootstrap_emitter_qualified_static_optional_args() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'bootstrap shim: qualified static optional-arg padding repair' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-qualified-static-optional-args "$emitter_path"
}

patch_bootstrap_emitter_preapplied_getstring_optional_arg() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'bootstrap shim: preapplied getString optional-arg repair' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-preapplied-getstring-optional-arg "$emitter_path"
}

patch_bootstrap_emitter_lambda_list_shim() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'bootstrap shim: Lambda.list repair' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-lambda-list-shim "$emitter_path"
}

patch_bootstrap_emitter_haxe_ds_list_shim() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'bootstrap shim: haxe.ds.List repair' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-haxe-ds-list-shim "$emitter_path"
}

patch_bootstrap_emitter_string_key_cast_index() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'bootstrap shim: string-key cast index repair' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-string-key-cast-index "$emitter_path"
}

patch_bootstrap_emitter_stringtools_hex_optional_digits() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"
  local marker='(* hxhx(stage3) bootstrap shim: StringTools.hex optional digits repair *)'

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal "$marker" "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-stringtools-hex-optional-digits "$emitter_path"
}

patch_bootstrap_emitter_mutable_int64_assignment() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"
  local marker='(* hxhx(stage3) bootstrap shim: mutable Int64 assignment repair *)'

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal "$marker" "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-mutable-int64-assignment "$emitter_path"
}

patch_bootstrap_emitter_int64_mixed_binops() {
  # Source-owned Int64 compound/binop lowering superseded this bootstrap-only
  # structural rewrite. Keep finalization stable by treating it as obsolete.
  return 0
}

patch_bootstrap_emitter_int64_static_helpers() {
  # Source-owned haxe.Int64 helper lowering superseded this bootstrap-only
  # structural rewrite. Keep finalization stable by treating it as obsolete.
  return 0
}

patch_bootstrap_emitter_float_compare_unknown_numeric() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal '| "==" -> if (!isIntExpr) (Obj.magic a) && (!isFloatExpr) (Obj.magic a) && isNegativeIntLikeExpr (Obj.magic a)' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-float-compare-unknown-numeric "$emitter_path"
}

patch_bootstrap_emitter_int_compare_precedence() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal '| "==" -> if (!isIntExpr) (Obj.magic a) && (!isIntExpr) (Obj.magic b)' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-int-compare-precedence "$emitter_path"
}

patch_bootstrap_emitter_float_modulo_mutable_local() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal 'bootstrap_float_mod_hint_1' "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-float-modulo-mutable-local "$emitter_path"
}

patch_bootstrap_emitter_plugin_dune_layout() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"
  local marker='(* hxhx(stage3) bootstrap shim: plugin dune layout repair *)'

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal "$marker" "$emitter_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-plugin-dune-layout "$emitter_path"
}

patch_bootstrap_js_target_core_native_js_lib_externs() {
  local build_dir="$1"
  local target_core_path="$build_dir/backend_js_JsTargetCore.ml"
  local marker='(* hxhx(stage3) bootstrap shim: js.lib extern native global repair *)'

  if [ ! -f "$target_core_path" ]; then
    return 0
  fi

  if file_contains_literal "$marker" "$target_core_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-js-target-core-native-js-lib-externs "$target_core_path"
}

patch_bootstrap_js_target_core_systools_static_bodies() {
  local build_dir="$1"
  local target_core_path="$build_dir/backend_js_JsTargetCore.ml"
  local registry_path="$build_dir/HxTypeRegistry.ml"
  local marker='(* hxhx(stage3) bootstrap shim: js target core SysTools static bodies *)'

  if [ -f "$target_core_path" ]; then
    if ! file_contains_literal "$marker" "$target_core_path" && ! file_contains_literal 'let emitKnownStaticFunctionBody = fun writer fullName fnName params ->' "$target_core_path"; then
      run_bootstrap_patch_helper patch-js-target-core-systools-static-bodies "$target_core_path"
    fi
  fi

  if [ -f "$registry_path" ]; then
    run_bootstrap_patch_helper patch-hxtype-registry-js-target-core-systools "$registry_path"
  fi
}

patch_bootstrap_clirouting_ocaml_eval_hxml() {
  local build_dir="$1"
  local clirouting_path="$build_dir/hxhx_CliRouting.ml"

  if [ ! -f "$clirouting_path" ]; then
    return 0
  fi

  run_bootstrap_patch_helper patch-cli-routing-ocaml-eval-hxml "$clirouting_path"
}

patch_bootstrap_typerstage_lowercase_static_receiver_guard() {
  local build_dir="$1"
  local typerstage_path="$build_dir/TyperStage.ml"
  local marker='(* hxhx(stage3) bootstrap shim: lower-case static receiver guard *)'

  if [ ! -f "$typerstage_path" ]; then
    return 0
  fi

  if file_contains_literal "$marker" "$typerstage_path"; then
    return 0
  fi

  run_bootstrap_patch_helper patch-typerstage-lowercase-static-receiver-guard "$typerstage_path"
}

patch_bootstrap_emitter_interactive_cli_progress() {
  local build_dir="$1"
  local emitter_path="$build_dir/EmitterStage.ml"
  local anchor='ignore (let shimName = ("Haxe_macro_Context" : string)'
  local marker='(* hxhx(stage3) bootstrap shim: InteractiveCLI.showProgress repair *)'
  local temp_path="$emitter_path.interactive_cli.tmp"
  local payload_path="$BOOTSTRAP_PATCH_PAYLOAD_DIR/interactive_cli_progress.mlpatch"

  if [ ! -f "$emitter_path" ]; then
    return 0
  fi

  if file_contains_literal "$marker" "$emitter_path"; then
    return 0
  fi

  insert_bootstrap_patch_before_anchor     "$emitter_path"     "$temp_path"     "$anchor"     "$payload_path"     "build-hxhx: failed to locate InteractiveCLI.showProgress repair anchor in EmitterStage.ml"

  mv "$temp_path" "$emitter_path"
}

finalize_bootstrap_dir() {
  local build_dir="$1"

  if [ ! -d "$build_dir" ]; then
    echo "Missing bootstrap dir: $build_dir" >&2
    exit 1
  fi

  if find "$build_dir" -maxdepth 1 -type f -name "*.ml.parts" | grep -q .; then
    bash "$ROOT/scripts/hxhx/hydrate-bootstrap-shards.sh" "$build_dir" >&2
  fi

  patch_bootstrap_emitter_root_sys_stdio "$build_dir"
  patch_bootstrap_emitter_project_generator_helper_calls "$build_dir"
  patch_bootstrap_emitter_load_template_fallback "$build_dir"
  patch_bootstrap_emitter_template_engine_condition "$build_dir"
  patch_bootstrap_emitter_php_syntax_empty_rest_calls "$build_dir"
  patch_bootstrap_emitter_php_boot_float_zero_compare "$build_dir"
  patch_bootstrap_emitter_php_boot_string_key_lookups "$build_dir"
  patch_bootstrap_emitter_haxe_io_eof_presence "$build_dir"
  patch_bootstrap_emitter_array_receiver_chain_lowering "$build_dir"
  patch_bootstrap_emitter_type_create_instance "$build_dir"
  patch_bootstrap_hxparser_interpolated_exprs "$build_dir"
  patch_bootstrap_hxparser_generic_function_decl "$build_dir"
  patch_bootstrap_hxparser_uppercase_helper_call "$build_dir"
  patch_bootstrap_native_parser_generic_arrow_constraints "$build_dir"
  patch_bootstrap_native_parser_expr_spacing "$build_dir"
  patch_bootstrap_emitter_typed_param_fallback "$build_dir"
  patch_bootstrap_emitter_parsed_arg_type_overlay "$build_dir"
  patch_bootstrap_stage1_std_root_termination "$build_dir"
  patch_bootstrap_emitter_allowed_ident_fallback "$build_dir"
  patch_bootstrap_emitter_typed_ty_map_copying "$build_dir"
  patch_bootstrap_emitter_typed_map_helper_obj_repr "$build_dir"
  patch_bootstrap_emitter_nested_call_arg_reprs "$build_dir"
  patch_bootstrap_emitter_module_name_lookup_raw_map "$build_dir"
  patch_bootstrap_emitter_typed_ty_ident_lookups "$build_dir"
  patch_bootstrap_emitter_return_expr_ty_ident_lookups "$build_dir"
  patch_bootstrap_emitter_expr_ident_ty_reads "$build_dir"
  patch_bootstrap_emitter_negative_unop_is_int_expr "$build_dir"
  patch_bootstrap_emitter_stmt_local_allowed_idents "$build_dir"
  patch_bootstrap_emitter_instance_call_receiver_forwarding "$build_dir"
  patch_bootstrap_emitter_instance_call_this_binding "$build_dir"
  patch_bootstrap_emitter_instance_method_value_binding "$build_dir"
  patch_bootstrap_emitter_allowed_ident_fallback "$build_dir"
  patch_bootstrap_emitter_instance_call_preapplied_arity "$build_dir"
  patch_bootstrap_emitter_string_length_fallback "$build_dir"
  patch_bootstrap_emitter_string_length_stdlib "$build_dir"
  patch_bootstrap_emitter_mutable_local_string_init_hints "$build_dir"
  patch_bootstrap_emitter_qualified_static_optional_args "$build_dir"
  patch_bootstrap_emitter_preapplied_getstring_optional_arg "$build_dir"
  patch_bootstrap_emitter_lambda_list_shim "$build_dir"
  patch_bootstrap_emitter_haxe_ds_list_shim "$build_dir"
  patch_bootstrap_emitter_string_key_cast_index "$build_dir"
  patch_bootstrap_emitter_stringtools_hex_optional_digits "$build_dir"
  patch_bootstrap_emitter_mutable_int64_assignment "$build_dir"
  patch_bootstrap_emitter_int64_mixed_binops "$build_dir"
  patch_bootstrap_emitter_int64_static_helpers "$build_dir"
  patch_bootstrap_emitter_preapplied_sig_fallback "$build_dir"
  patch_bootstrap_emitter_float_compare_unknown_numeric "$build_dir"
  patch_bootstrap_emitter_int_compare_precedence "$build_dir"
  patch_bootstrap_emitter_float_modulo_mutable_local "$build_dir"
  patch_bootstrap_emitter_plugin_dune_layout "$build_dir"
  patch_bootstrap_js_target_core_native_js_lib_externs "$build_dir"
  patch_bootstrap_js_target_core_systools_static_bodies "$build_dir"
  patch_bootstrap_typerstage_lowercase_static_receiver_guard "$build_dir"
  patch_bootstrap_clirouting_ocaml_eval_hxml "$build_dir"
  patch_bootstrap_emitter_interactive_cli_progress "$build_dir"
  patch_bootstrap_emitter_nested_call_arg_reprs "$build_dir"
  patch_bootstrap_emitter_typed_map_helper_obj_repr "$build_dir"
  patch_bootstrap_emitter_module_name_lookup_raw_map "$build_dir"
  patch_bootstrap_emitter_typed_ty_ident_lookups "$build_dir"
  patch_bootstrap_emitter_return_expr_ty_ident_lookups "$build_dir"
  patch_bootstrap_emitter_expr_ident_ty_reads "$build_dir"
}

finalize_bootstrap_dir "$1"
