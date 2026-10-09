package backend.cpp;

/**
	Resolve storage without changing the semantic class arguments. Ordinary values
	declared as T retain null when T becomes Int or Bool; Box<T> still becomes
	Box<Int>, not Box<Null<Int>>. Function parameter/results follow the same rule.
	The caller supplies its exact validated function or field type application.
 */
function resolve(type:TyType, semantic:TyType->TyType, ?casts:CppManagedCastPlan):TyType
	return fromApplied(type, semantic(type), casts);

/**
	Retain generic null storage in an already validated declaration/application pair.
	Function-valued fields need the same parameter and result transport as their
	initializer closures. Concrete function declarations keep their scalar ABI.
	Callers must obtain the applied type from exact owned facts or substitution.
 */
function fromApplied(declared:TyType, applied:TyType, ?casts:CppManagedCastPlan):TyType {
	if (declared.isTypeParameter() && (applied.getSemanticKey() == "primitive:Int" || applied.getSemanticKey() == "primitive:Bool"))
		return TyType.nullable(applied);
	if (declared.isFunction()) {
		final parameters = declared.getFunctionArguments();
		final appliedParameters = applied.getFunctionArguments();
		if (!applied.isFunction() || parameters.length != appliedParameters.length)
			throw "managed applied function storage requires matching parameter shapes";
		return applied.withFunctionTypes([
			for (index in 0...parameters.length)
				fromApplied(parameters[index], appliedParameters[index], casts)
		], fromApplied(declared.getFunctionReturn(), applied.getFunctionReturn(), casts));
	}
	return casts == null ? applied : casts.appliedAbstractStorage(declared, applied);
}
