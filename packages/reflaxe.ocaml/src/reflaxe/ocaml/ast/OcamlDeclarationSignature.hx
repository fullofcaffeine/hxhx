package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.lowered.OcamlDynamicEqualityPlan.OcamlDynamicCarrierModel;
import reflaxe.ocaml.lowered.OcamlMonomorphicClassPlanner;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/** Concrete declaration types used to constrain recursive module exports. */
typedef OcamlDeclarationSignature = {
	final parameters:Array<OcamlTypeExpr>;
	final result:OcamlTypeExpr;
};

/**
	Projects known declaration carriers without expanding the optimized call family.

	A Haxe record parameter uses the same boxed table selected by ordinary field
	access and coercion. Its OCaml type is therefore Obj.t, not a guessed record.
	Iterators, key/value pairs, and FileStat use other representations and remain
	unavailable here. Arrays of supported elements use the existing checked
	container mapping, including the same storage for optional arrays. Other
	private runtime carriers, unresolved types, and generic or extern declarations
	remain unavailable; their signatures need their own representation proof.
	Class declarations can also use a direct record after the whole program's
	inheritance check; this does not admit new field optimizations. The recursive
	module interface checks each generated function against the selected types. Ordinary
	modules keep their existing inferred function types and generated text.
**/
function projectDeclarationSignature(parameters:Array<Type>, result:Type, representations:OcamlRepresentationRegistry, nominalType:Type->OcamlTypeExpr,
		context:CompilationContext):Null<OcamlDeclarationSignature> {
	final parameterTypes:Array<OcamlTypeExpr> = [];
	for (parameter in parameters) {
		final type = declarationCarrier(parameter, representations, nominalType, context);
		if (type == null)
			return null;
		parameterTypes.push(type);
	}
	final resultType = declarationCarrier(result, representations, nominalType, context);
	return resultType == null ? null : {parameters: parameterTypes, result: resultType};
}

/** Only explicit, existing storage choices may become exported declaration types. */
private function declarationCarrier(type:Type, representations:OcamlRepresentationRegistry, nominalType:Type->OcamlTypeExpr,
		context:CompilationContext):Null<OcamlTypeExpr> {
	return switch (type) {
		case TType(reference, parameters):
			final definition = reference.get();
			declarationCarrier(TypeTools.applyTypeParameters(definition.type, definition.params, parameters), representations, nominalType, context);
		case TAnonymous(reference):
			switch (reference.get().status) {
				case AClosed if (OcamlDynamicCarrierModel.anonymousUsesHxAnon(type)):
					// This is the existing structural runtime boundary, not a fallback
					// for unknown Haxe types. No boxing, cast, or conversion is added.
					TIdent("Obj.t");
				case _: null;
			}
		case TAbstract(reference, []) if (reference.get().pack.length == 0):
			switch (reference.get().name) {
				case "Int": TIdent("int");
				case "Bool": TIdent("bool");
				case "Void": TIdent("unit");
				case _: null;
			}
		case TAbstract(reference, [inner]) if (reference.get().pack.length == 0
			&& reference.get().name == "Null"
			&& isStandardArray(TypeTools.follow(inner))):
			// Null<Array<T>> uses the array carrier and the existing null sentinel.
			// This is not permission to erase arbitrary nullable scalar boundaries.
			declarationCarrier(TypeTools.follow(inner), representations, nominalType, context);
		case TInst(_, [element]) if (isStandardArray(type)):
			if (declarationCarrier(element, representations, nominalType, context) == null) {
				null;
			} else {
				// The normal type mapper obtains request-bound container authority.
				// A plain target name cannot authorize an exported array type.
				switch (nominalType(type)) {
					case carrier = TRuntimeApp(_, [_]): carrier;
					case _: null;
				}
			}
		case TInst(reference, []):
			final definition = reference.get();
			switch (definition.kind) {
				case KTypeParameter(_): null;
				case _ if (definition.pack.length == 0 && definition.name == "String"): TIdent("string");
				case _ if (representations.monomorphicClassForType(type) != null): nominalType(type);
				case _
					if (context.virtualTypesComputed
						&& !OcamlRepresentationRegistry.isExactBytes(type)
						&& (definition.pack.length == 0 || definition.pack[0] != "ocaml")
						&& OcamlMonomorphicClassPlanner.hasDirectRecordLayout(definition, context)): nominalType(type);
				case _: null;
			}
		case TEnum(reference, []) if (!reference.get().isExtern && reference.get().params.length == 0):
			final definition = reference.get();
			representations.nativeEnumValue(definition.pack.concat([definition.name]).join(".")) == null ? null : nominalType(type);
		case _: null;
	}
}

/** Recognizes the source Array declaration; checked storage still comes from its owner. */
private function isStandardArray(type:Type):Bool {
	return switch (type) {
		case TInst(reference, [_]): final definition = reference.get(); definition.pack.length == 0 && definition.module == "Array" && definition.name == "Array";
		case _: false;
	};
}
#end
