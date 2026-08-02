package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.ClassType;
import haxe.macro.Type.ClassField;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
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

/** Typed evidence for one exact target-authored standard Map pair iterator. */
typedef OcamlStandardMapPairProducer = {
	final sourceDeclarationId:String;
	final iteratorSemanticTypeId:String;
	final keySemanticTypeId:String;
	final valueSemanticTypeId:String;
	final proofId:String;
	final proofClaim:String;
}

/**
	Classifies standard Map declarations from their typed source identity.
**/
class OcamlStandardMapCarrierContract {
	public static inline final PAIR_PRODUCER_PROOF_ID = "target-native-standard-map-pair-producer-v1";
	public static inline final PAIR_PRODUCER_PROOF_CLAIM = "The final typed iterator initializer is the exact target-authored NativeHxMapIterator.of_array call around NativeHxMap.pairs_string, pairs_int, or pairs_object. The nested pair helper's Array<{key:K,value:V}> result determines the key and value types before field syntax. A shared native symbol, an arbitrary Iterator of anonymous objects, anonymous shape, or the key/value field names alone do not satisfy this proof.";

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
		Recognizes the final target-authored standard Map pair iterator.

		The target's standard `StringMap`, `IntMap`, and `ObjectMap` methods are
		inlined before this planner runs. Their final typed form is the exact
		`NativeHxMapIterator.of_array(NativeHxMap.pairs_*(map))` helper chain.
		Retaining that complete declaration chain lets later field planning
		preserve the tuple carrier without accepting arbitrary pair-shaped values.
	**/
	public static function pairProducerForExpression(expression:TypedExpr):Null<OcamlStandardMapPairProducer> {
		final selected = switch (expression.expr) {
			case TCall({expr: TField(_, FStatic(iteratorClassRef, iteratorFieldRef))}, [pairsExpression]):
				final iteratorClass = iteratorClassRef.get();
				final iteratorSource = OcamlTypedDeclarationIdentity.canonicalSourceName(iteratorClass.meta,
					(iteratorClass.pack ?? []).concat([iteratorClass.name]).join("."), "a class");
				if (iteratorSource != "haxe.ds.NativeHxMapIterator"
					|| iteratorFieldRef.get().name != "of_array") null; else switch (pairsExpression.expr) {
					case TCall({expr: TField(_, FStatic(mapClassRef, pairsFieldRef))}, [_]):
						final mapClass = mapClassRef.get();
						final mapSource = OcamlTypedDeclarationIdentity.canonicalSourceName(mapClass.meta,
							(mapClass.pack ?? []).concat([mapClass.name]).join("."), "a class");
						final pairFunction = pairsFieldRef.get().name;
						if (mapSource == "haxe.ds.NativeHxMap"
							&& (pairFunction == "pairs_string" || pairFunction == "pairs_int" || pairFunction == "pairs_object")) {
							{pairsExpression: pairsExpression, pairFunction: pairFunction};
						} else null;
					case _:
						null;
				}
			case _:
				null;
		}
		if (selected == null)
			return null;
		final types = pairTypesFromArray(selected.pairsExpression.t);
		if (types == null
			|| (selected.pairFunction == "pairs_string" && types.key != "String")
			|| (selected.pairFunction == "pairs_int" && types.key != "Int")
			|| (selected.pairFunction == "pairs_object" && (types.key == "String" || types.key == "Int")))
			return null;
		return {
			sourceDeclarationId: 'haxe.ds.NativeHxMapIterator.of_array(haxe.ds.NativeHxMap.${selected.pairFunction})',
			iteratorSemanticTypeId: TypeTools.toString(expression.t),
			keySemanticTypeId: types.key,
			valueSemanticTypeId: types.value,
			proofId: PAIR_PRODUCER_PROOF_ID,
			proofClaim: PAIR_PRODUCER_PROOF_CLAIM
		};
	}

	static function pairTypesFromArray(type:Type):Null<{key:String, value:String}> {
		return switch (TypeTools.follow(type)) {
			case TInst(arrayRef, [pairType]) if (arrayRef.get().pack.length == 0 && arrayRef.get().name == "Array"):
				switch (TypeTools.follow(pairType)) {
					case TAnonymous(anonymousRef): pairTypesFromFields(anonymousRef.get().fields);
					case _:
						null;
				}
			case _:
				null;
		}
	}

	static function pairTypesFromFields(fields:Array<ClassField>):Null<{key:String, value:String}> {
		final key = Lambda.find(fields, field -> field.name == "key");
		final value = Lambda.find(fields, field -> field.name == "value");
		return key == null || value == null ? null : {
			key: TypeTools.toString(key.type),
			value: TypeTools.toString(value.type)
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
