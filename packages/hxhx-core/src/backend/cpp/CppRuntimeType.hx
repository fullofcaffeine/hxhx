package backend.cpp;

/**
	Admit only runtime operations implemented by the C++ target before publication.

	The current implementation consumes instance tests for the four standard Map
	specializations. Class objects and other target categories remain explicit
	unsupported operations. Every admitted target must have its indexed provider.
 */
function validate(program:CppTypedProgramProjection):Void {
	final plan = new CppRuntimeTypePlan(program);
	for (operation in plan.getOperations())
		mapTarget(operation.occurrence);
}

/** Recover facts through the current executable, never through the marker's printed name or copied shape. */
function require(expression:HxExpr, scope:CppRenderScope):TypedBackendRuntimeTypeOccurrence {
	if (scope == null)
		throw "C++ runtime type operand requires an executable scope";
	final occurrence = if (scope.executableLocals != null) {
		scope.executableLocals.requireRuntimeType(expression);
	} else if (scope.functionProjection != null) {
		scope.functionProjection.requireRuntimeType(expression);
	} else {
		throw "C++ runtime type operand requires exact executable facts";
	};
	mapTarget(occurrence);
	return occurrence;
}

/** A rendered operand appears once, including when its represented value is null or belongs to another Map family. */
function render(occurrence:TypedBackendRuntimeTypeOccurrence, value:String, valueCppType:String, mapKeyCppType:String, scope:CppRenderScope):String {
	final target = mapTarget(occurrence);
	// The existing Map carrier owns key-family selection. A generic or erased
	// key must not enter its historical catch-all ObjectMap branch.
	if (valueCppType != null
		&& StringTools.startsWith(valueCppType, "std::shared_ptr<Map<")
		&& (mapKeyCppType == "int" || mapKeyCppType == "std::string" || StringTools.startsWith(mapKeyCppType, "std::shared_ptr<")))
		return "__hxhx_is_type(" + value + ', "' + target + '")';
	if (mapKeyCppType.length == 0 && isKnownNonMap(occurrence.getValue(), valueCppType, scope))
		return "(static_cast<void>(" + value + "), false)";
	throw "C++ backend does not support runtime type operands for an erased or unplanned Map test value";
}

/**
	Prove a negative result only for concrete native values or an exact new root class.
	A shared pointer alone cannot prove non-membership: its pointee may be a Map
	subclass or an external representation. Constructor facts distinguish a user
	class named IntMap from the standard provider without guessing from its name.
 */
private function isKnownNonMap(expression:HxExpr, cppType:String, scope:CppRenderScope):Bool {
	if (cppType == null)
		return false;
	switch cppType {
		case "bool" | "int" | "double" | "float" | "std::string" | "std::nullptr_t":
			return true;
		case _:
	}
	if (StringTools.startsWith(cppType, "std::vector<"))
		return true;
	switch expression {
		case ENew(_, _):
			if (scope.classLookup == null || scope.classLookup.typedProgram == null)
				return false;
			final construction = scope.executableLocals != null ? scope.executableLocals.requireConstructor(expression) : scope.functionProjection.requireConstructor(expression);
			final identity = construction.getConstructedType().getNominalIdentity();
			if (identity == null)
				return false;
			final program = scope.classLookup.typedProgram;
			final facts = program.requireClass(program.requireClassIdentity(identity.getCanonicalName())).requireSemanticFacts();
			return switch facts.getNominalKind() {
				case ClassInstance: !facts.getIsExtern() && !facts.getIsInterface() && facts.getSuperType() == null;
				case _: false;
			};
		case _:
			return false;
	}
}

/** The closed target family comes from shared declaration identity, not a source alias or marker payload. */
private function mapTarget(occurrence:TypedBackendRuntimeTypeOccurrence):String {
	occurrence.assertCurrent();
	if (occurrence.getValue() == null)
		throw "C++ backend does not support runtime type operands that produce class values";
	final target = switch occurrence.getTarget().getKind() {
		case Nominal(identity):
			switch identity.getCanonicalName() {
				case "haxe.ds.IntMap" | "haxe.ds.StringMap" | "haxe.ds.ObjectMap" | "haxe.ds.EnumValueMap": identity.getCanonicalName();
				case _: throw "C++ backend does not support runtime type operands for " + identity.getCanonicalName();
			}
		case _: throw "C++ backend does not support runtime type operands for " + occurrence.getTarget().getSemanticKey();
	};
	var valueType = occurrence.getValueType();
	while (valueType != null && valueType.isNullWrapped())
		valueType = valueType.getNullableInner();
	if (valueType == null || valueType.isDynamic() || valueType.hasUnknownComponent() || valueType.isUnresolved() || valueType.isTypeParameter()
		|| valueType.hasOpenMethodParameter())
		throw "C++ backend does not support runtime type operands for an erased or unplanned Map test value: "
			+ (valueType == null ? "missing source type" : valueType.getSemanticKey());
	return target;
}
