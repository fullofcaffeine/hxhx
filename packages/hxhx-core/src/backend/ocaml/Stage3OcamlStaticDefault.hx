package backend.ocaml;

import TypedBackendClassSemanticFacts.TypedBackendNominalKind;

/**
	The value of a Stage3 static field that has no initializer.

	Stage3 uses the static-target default: `0`, `0.0` or `false` for a field
	whose OCaml carrier is an unboxed int, float or bool (non-null Int, Float
	and Bool, and abstracts over them such as `enum abstract Kind(Int)` or
	`abstract Meters(Float)`), and the runtime null for a field stored as a
	reference (String, nullable types, Dynamic, functions, anonymous
	structures, classes and enums). Upstream eval prints `null` for every
	uninitialized static, including non-null Int, Float and Bool; that
	difference is tracked as haxe_ocaml-a8wbz.

	Stage3 used to emit `(Obj.magic 0)` for every type. For a String that is
	the immediate `0`, not the runtime null sentinel, so `HxString.toStdString`
	did not recognize it as null and printing the field crashed.

	A type this module cannot prove is a reference keeps `(Obj.magic 0)`, the
	old immediate value. That covers an unresolved type and an abstract whose
	declaration is not part of this request, such as `UInt` or `haxe.Int32`
	when the runtime provides them: an immediate is the safe value for an int
	carrier.
**/
function value(type:Null<TyType>, kindOf:String->Null<TypedBackendNominalKind>):String {
	final seen:Map<String, Bool> = [];
	var current = type;
	while (true) {
		if (current == null || current.isUnknown() || current.isUnresolved())
			return "(Obj.magic 0)";
		current = TyAliasExpansion.reveal(current);
		if (current.isNullable() || current.isDynamic() || current.isFunction() || current.isAnonymous())
			return "(Obj.magic HxRuntime.hx_null)";
		switch current.getSemanticKey() {
			case "primitive:Int":
				return "0";
			case "primitive:Float":
				return "0.";
			case "primitive:Bool":
				return "false";
			case "primitive:String":
				return "(Obj.magic HxRuntime.hx_null)";
			case _:
		}
		final identity = current.getNominalIdentity();
		if (identity == null || seen.exists(identity.getCanonicalName()))
			return "(Obj.magic 0)";
		seen.set(identity.getCanonicalName(), true);
		switch kindOf(identity.getCanonicalName()) {
			case ClassInstance | EnumValue:
				return "(Obj.magic HxRuntime.hx_null)";
			case AbstractValue(underlying):
				current = underlying;
			case null:
				return "(Obj.magic 0)";
		}
	}
}
