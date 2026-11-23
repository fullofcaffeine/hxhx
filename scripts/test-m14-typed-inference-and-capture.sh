#!/usr/bin/env bash
# Typed-inference and capture tests (npm run test:m14:typed-inference-and-capture).
# One command per line, so pull requests that add tests do not conflict.
# Add a new test in alphabetical order in the sorted section below, never at the end.
set -euxo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

haxe test/m14_abstract_constructor_result_test.hxml
haxe test/m14_addition_operand_inference_test.hxml
haxe test/m14_arithmetic_operand_inference_test.hxml
haxe test/m14_array_access_inference_test.hxml
haxe test/m14_comparison_operand_inference_test.hxml
haxe test/m14_null_default_inference_test.hxml
haxe test/m14_omitted_optional_callback_context_test.hxml
haxe test/m14_conditional_branch_join_test.hxml
haxe test/m14_optional_field_nullable_read_test.hxml
haxe test/m14_core_type_header_conversion_test.hxml
haxe test/m14_type_using_metadata_test.hxml
haxe test/m14_enum_abstract_context_value_test.hxml
haxe test/m14_recursive_local_function_inference_test.hxml
haxe test/m14_recursive_typedef_callback_test.hxml
haxe test/m14_assigned_container_inference_test.hxml
haxe test/m14_generic_callback_input_inference_test.hxml
haxe test/m14_callback_structure_input_inference_test.hxml
haxe test/m14_switch_array_branch_inference_test.hxml
haxe test/m14_class_value_cast_pattern_test.hxml
haxe test/m14_callback_field_requirement_input_test.hxml

# Sorted section: add new tests here, in alphabetical order.
haxe test/m14_abstract_field_operator_test.hxml
haxe test/m14_anonymous_argument_variance_test.hxml
haxe test/m14_array_literal_switch_test.hxml
haxe test/m14_array_null_argument_test.hxml
haxe test/m14_bitwise_parameter_inference_test.hxml
haxe test/m14_bound_input_keeps_type_test.hxml
haxe test/m14_class_argument_bounds_test.hxml
haxe test/m14_compiler_json_value_integration_test.hxml
haxe test/m14_discarded_control_test.hxml
haxe test/m14_dynamic_generic_evidence_test.hxml
haxe test/m14_dynamic_join_transparent_test.hxml
haxe test/m14_extern_inline_generic_test.hxml
haxe test/m14_extern_inline_storage_test.hxml
haxe test/m14_extractor_pattern_type_test.hxml
haxe test/m14_method_local_construction_test.hxml
haxe test/m14_named_pattern_projection_test.hxml
haxe test/m14_native_class_storage_test.hxml
haxe test/m14_native_stored_callback_views_test.hxml
haxe test/m14_neko_enum_payload_count_test.hxml
haxe test/m14_neko_native_array_primitives_test.hxml
haxe test/m14_null_compare_binds_nullable_test.hxml
haxe test/m14_null_destination_input_test.hxml
haxe test/m14_null_local_assignment_test.hxml
haxe test/m14_open_value_test.hxml
haxe test/m14_optional_field_type_equality_test.hxml
haxe test/m14_primitive_constructor_effects_test.hxml
haxe test/m14_regex_literal_syntax_test.hxml
haxe test/m14_statement_control_projection_test.hxml
haxe test/m14_structural_field_over_extension_test.hxml
haxe test/m14_try_assignment_value_test.hxml
haxe test/m14_type_parameter_bounds_test.hxml
haxe test/m14_typed_backend_capture_catalog_test.hxml
haxe test/m14_typed_capture_lowering_test.hxml
haxe test/m14_typed_capture_plan_test.hxml
haxe test/m14_typed_capture_static_method_test.hxml
haxe test/m14_untyped_function_body_syntax_test.hxml
haxe test/m14_var_declaration_group_test.hxml
