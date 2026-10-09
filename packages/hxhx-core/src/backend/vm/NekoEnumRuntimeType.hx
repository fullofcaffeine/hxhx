package backend.vm;

/**
	Attach the public Neko enum-owner slot only at exact constructor boundaries.

	The selected function or singleton field comes from the typed declaration
	inventory. Neither a readable enum name nor the shape of an anonymous object
	authorizes tagging. Existing instances retain the original descriptor if an
	explicit untyped operation later replaces the source-visible type binding.
**/
function tagValue(context:NekoEmitContext, value:String):String {
	final identity = NekoEnumConstructorPlan.resultOwner(context);
	if (identity == null)
		return value;
	final target = new TypedRuntimeTypeTarget(EnumDeclaration(new TyNominalTypeId(identity)));
	final key = NekoRuntimeTypeRegistry.requireTarget(context.typedProgram, target);
	return context.typedProgram.runtimeHelperName("__hxhx_tag_enum_value")
		+ "("
		+ context.typedProgram.runtimeHelperName("__hxhx_runtime_type_definition")
		+ "("
		+ haxe.Json.stringify(key)
		+ "), "
		+ value
		+ ")";
}

/** Implement only the selected runtime operation; Haxe owns declaration selection. */
function renderPrelude(out:Array<String>, program:NekoTypedProgramProjection):Void {
	out.push("var " + program.runtimeHelperName("__hxhx_tag_enum_value") + " = function(owner, value) {");
	out.push("  if (value == null || $typeof(value) != $tobject) $throw(\"enum constructor requires an object value\");");
	out.push("  $objset(value, $hash(\"__enum__\"), owner);");
	out.push("  return value;");
	out.push("}");
}
