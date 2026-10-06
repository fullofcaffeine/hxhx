package backend.cpp;

/** Compound writes reuse binary operation policy, then require its result to fit the selected place. */
function requireType(op:String, target:TyType, source:TyType):Void {
	final result = CppManagedStringConcat.selects(op, target,
		source) ? CppManagedStringConcat.resultType(target, source) : CppManagedInteger.resultType(op, target, source);
	if (!CppManagedValueTransfer.accepts(target, result))
		throw "managed compound assignment requires an explicit typed conversion";
}

/** The caller saves the old value before RHS effects and publishes only the completed result. */
function compute(op:String, target:TyType, source:TyType, before:String, value:String, destination:String, prefix:String, indent:String):Array<String> {
	requireType(op, target, source);
	return CppManagedStringConcat.selects(op, target,
		source) ? CppManagedStringConcat.compute(target, source, before, value, destination,
		indent) : CppManagedInteger.compute(op, target, source, before, value, destination, prefix, indent);
}
