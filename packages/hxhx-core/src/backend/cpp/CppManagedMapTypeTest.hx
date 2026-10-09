package backend.cpp;

import backend.cpp.CppManagedCallContext.CppManagedEnclosingApplication;

/** These standard families use Map payloads even when their providers are class declarations. */
function selectsTarget(occurrence:TypedBackendRuntimeTypeOccurrence):Bool {
	return switch occurrence.getTarget().getKind() {
		case Nominal(identity): [
				"haxe.ds.IntMap",
				"haxe.ds.StringMap",
				"haxe.ds.ObjectMap",
				"haxe.ds.EnumValueMap"
			].contains(identity.getCanonicalName());
		case _: false;
	};
}

/**
	Admit exact Map instance tests whose managed representation is already known.
	A Map's key type selects its runtime family. The stored value still decides
	null membership, and its expression must execute even for a known mismatch.
	Erased operands need runtime identity storage and remain unsupported here.
	Class values require descriptor emission rather than this Boolean operation.
 */
function matchesFamily(occurrence:TypedBackendRuntimeTypeOccurrence, ?classes:CppManagedClassStorage, ?enums:CppManagedEnumDescriptors,
		?context:CppManagedEnclosingApplication):Bool {
	occurrence.assertCurrent();
	if (occurrence.getValue() == null)
		throw "managed C++ program does not support runtime type operands that produce class values";
	final target = switch occurrence.getTarget().getKind() {
		case Nominal(identity): identity.getCanonicalName();
		case _: throw "managed C++ program does not support runtime type operands for " + occurrence.getTarget().getSemanticKey();
	};
	if (!selectsTarget(occurrence))
		throw "managed C++ program does not support runtime type operands for " + target;
	if (context != null && classes == null)
		throw "managed runtime context requires its program-owned class storage";
	var type = classes == null ? occurrence.getValueType() : classes.runtimeOperandType(occurrence, context);
	while (type != null && type.getNullableInner() != null)
		type = type.getNullableInner();
	if (type == null || type.isDynamic() || type.hasUnknownComponent() || type.isUnresolved() || type.isTypeParameter() || type.hasOpenMethodParameter())
		throw "managed C++ program does not support runtime type operands for an erased or unplanned Map test value";
	CppManagedClosureAbi.assertComplete(type);
	final identity = type.getNominalIdentity();
	if (identity != null && identity.getCanonicalName() == "haxe.ds.Map") {
		// Use the same admission as allocation. A new key representation must be
		// implemented there before its type test can claim native support here.
		final storage = CppManagedMapStorage.select(type, classes, enums);
		return storage.runtimeClass == target;
	}
	if ((identity != null && identity.getCanonicalName() == "Array")
		|| ["primitive:Bool", "primitive:Int", "primitive:String"].indexOf(type.getSemanticKey()) >= 0)
		return false;
	if (identity != null && classes != null) {
		// A represented ordinary instance cannot become a Map through matching
		// display names. This also validates the representation of its value.
		if (!classes.isInstanceValue(type))
			throw "managed Map test lacks an instance representation for " + type.getSemanticKey();
		return false;
	}
	throw "managed C++ program does not support runtime type operands for an erased or unplanned Map test value: " + type.getSemanticKey();
}

/** Preserve admission before publication for every selected executable catalog. */
function validate(catalog:TypedBackendRuntimeTypeCatalog, ?classes:CppManagedClassStorage, ?enums:CppManagedEnumDescriptors,
		?context:CppManagedEnclosingApplication):Void {
	for (occurrence in catalog.getEntries())
		matchesFamily(occurrence, classes, enums, context);
}

/** Root the evaluated operand once, including mismatched families and null values. */
function render(input:{
	occurrence:TypedBackendRuntimeTypeOccurrence,
	?classes:CppManagedClassStorage,
	?enums:CppManagedEnumDescriptors,
	?context:CppManagedEnclosingApplication,
	heap:String,
	destination:String,
	renderValue:(HxExpr, String, String) -> Array<String>
}, indent:String):Array<String> {
	final matches = matchesFamily(input.occurrence, input.classes, input.enums, input.context);
	final operand = input.destination + "_type_operand";
	final lines = [
		indent + "{",
		indent + "  hxhx::managed::Root<hxhx::managed::Value> " + operand + "(" + input.heap + ");"
	];
	for (line in input.renderValue(input.occurrence.getValue(), operand, indent + "  "))
		lines.push(line);
	final test = matches ? operand + ".get().kind() != hxhx::managed::ValueKind::Null" : "false";
	lines.push(indent + "  " + input.destination + ".set(hxhx::managed::Value::boolean(" + test + "));");
	lines.push(indent + "}");
	return lines;
}
