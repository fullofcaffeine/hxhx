package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.ClassType;
import haxe.macro.Type;
import reflaxe.ocaml.ast.OcamlTypeExpr;

/**
	The concrete OCaml carrier required by one standard Haxe Map declaration.

	The kind comes from the canonical Haxe source declaration, not the shared
	`HxMap` native symbol. This preserves key semantics after `@:native` rewrites
	`StringMap`, `IntMap`, and `ObjectMap` to the same target module.
**/
enum OcamlStandardMapCarrierKind {
	StringKeys;
	IntKeys;
	ObjectIdentityKeys;
}

/**
	Classifies standard Map declarations from their typed source identity.
**/
class OcamlStandardMapCarrierContract {
	/**
		Returns the standard carrier kind, or `null` for a non-Map declaration.
	**/
	public static function kindForClass(classType:ClassType):Null<OcamlStandardMapCarrierKind> {
		final rewrittenName = (classType.pack ?? []).concat([classType.name]).join(".");
		final sourceName = OcamlTypedDeclarationIdentity.canonicalSourceName(classType.meta, rewrittenName, "a class");
		return switch (sourceName) {
			case "haxe.ds.StringMap": StringKeys;
			case "haxe.ds.IntMap": IntKeys;
			case "haxe.ds.ObjectMap": ObjectIdentityKeys;
			case _: null;
		};
	}

	/**
		Materializes the exact OCaml carrier for one standard Map declaration.

		`lowerType` keeps nested key and value types under the compiler's ordinary
		type-lowering contract while this owner selects only the Map family.
	**/
	public static function carrierForClass(classType:ClassType, parameters:Array<Type>, lowerType:Type->OcamlTypeExpr):Null<OcamlTypeExpr> {
		return switch (kindForClass(classType)) {
			case StringKeys:
				final value = parameters.length > 0 ? lowerType(parameters[0]) : OcamlTypeExpr.TIdent("Obj.t");
				OcamlTypeExpr.TApp("HxMap.string_map", [value]);
			case IntKeys:
				final value = parameters.length > 0 ? lowerType(parameters[0]) : OcamlTypeExpr.TIdent("Obj.t");
				OcamlTypeExpr.TApp("HxMap.int_map", [value]);
			case ObjectIdentityKeys:
				final key = parameters.length > 0 ? lowerType(parameters[0]) : OcamlTypeExpr.TIdent("Obj.t");
				final value = parameters.length > 1 ? lowerType(parameters[1]) : OcamlTypeExpr.TIdent("Obj.t");
				OcamlTypeExpr.TApp("HxMap.obj_map", [key, value]);
			case null:
				null;
		};
	}
}
#end
