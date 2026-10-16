package backend.ocaml;

/**
	Apply declared parameter defaults before the authored method body starts.
	The incoming null sentinel selects a default lazily. Rebinding the exact local
	name keeps later mutation and closure capture under the existing body owner.
	Defaults run in declared parameter order.
 */
function render(input:{
	projection:TypedBackendFunctionProjection,
	names:Stage3OcamlLocalNames,
	body:String,
	emit:(expression:HxExpr, actual:TyType, expected:TyType) -> String
}):String {
	if (!input.projection.hasDefaults())
		return input.body;
	final parameters = input.projection.getParameters();
	final defaults = input.projection.getDefaults();
	var result = input.body;
	var index = defaults.length;
	while (index-- > 0) {
		final value = defaults[index];
		final parameter = parameters[value.slot];
		final name = input.names.targetName(parameter.getProjectedName());
		final fallback = input.emit(value.expression, value.type, parameter.getBinding().getType());
		result = "(let "
			+ name
			+ " = (if HxRuntime.is_null (Obj.repr "
			+ name
			+ ") then ("
			+ fallback
			+ ") else "
			+ name
			+ ") in "
			+ result
			+ ")";
	}
	return result;
}
