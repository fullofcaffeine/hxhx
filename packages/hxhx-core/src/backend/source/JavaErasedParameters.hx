package backend.source;

typedef JavaErasedParameterPlan = {
	final signature:String;
	final prologue:Array<String>;
	final admitsCallableFirstArgument:Bool;
};

/**
	Restore Boolean locals at Java's existing Object-valued helper call boundary.
	Method references keep their Object argument ABI. The exact parameter catalog
	selects which incoming values need a checked Boolean cast before the body can
	use them in guards, logical operators, or assignments. Boxed locals preserve
	a written null; unrelated parameter representations remain unchanged.
 */
@:access(backend.source.SourceTargetCommon)
function plan(projection:TypedBackendFunctionProjection):JavaErasedParameterPlan {
	projection.requireCaptureCatalog().assertCurrent();
	final signature = new Array<String>();
	final prologue = new Array<String>();
	var next = 0;
	for (parameter in projection.getParameters()) {
		final name = SourceTargetCommon.sanitizeJavaIdentifier(parameter.getProjectedName());
		final type = TyAliasExpansion.revealNonNullable(parameter.getBinding().getType());
		if (type.getSemanticKey() != "primitive:Bool") {
			signature.push("Object " + name);
			continue;
		}
		var incoming:String;
		do {
			incoming = "_hx_bool_argument_" + next++;
		} while (projection.getLocalCatalog().findByProjectedName(incoming) != null);
		signature.push("Object " + incoming);
		prologue.push("Boolean " + name + " = (Boolean) " + incoming + ";");
	}
	final parameters = projection.getParameters();
	final first = parameters.length == 0 ? null : TyAliasExpansion.revealNonNullable(parameters[0].getBinding().getType());
	return {
		signature: signature.join(", "),
		prologue: prologue,
		admitsCallableFirstArgument: first != null && (first.isFunction() || first.isDynamic() || first.isTypeParameter())
	};
}
