package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.lowered.OcamlDynamicEqualityPlan.OcamlDynamicCarrierModel;
import reflaxe.ocaml.lowered.OcamlMonomorphicClassPlanner;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.lowered.OcamlStandardMapCarrierModel.OcamlStandardMapCarrierContract;

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
	unavailable here. Arrays and standard maps of supported elements use their
	existing checked container mappings. Nullable maps use the ordinary mapper's
	storage, including boxed Map abstracts. Other supported class, String, and
	Array references retain their existing storage when nullable. Other
	private runtime carriers, unresolved types, and generic or extern declarations
	remain unavailable; their signatures need their own representation proof.
	Class declarations can also use a direct record after the whole program's
	inheritance check; this does not admit new field optimizations. Ordinary
	inherited classes can name their existing dispatch records after that check.
	Their methods and base-prefix layout remain owned by ordinary class emission.
	The recursive
	interface may name an ordinary non-generic enum's existing variant type even
	when no optimized enum-returning function registered a result-carrier proof.
	This only exports the declaration; it does not authorize new call conversions.
	Nullable enums retain the mapper's existing boxed null-or-variant carrier.
	Function types use the ordinary curried callback ABI only when every argument
	and result has an admitted declaration carrier; zero arguments use unit.
	Optional callback arguments currently require String's existing null sentinel.
	Other optional types need a separate proof of their nullable call boundary.
	The recursive module interface checks each generated function against the selected types. Ordinary
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
	final mapParameters = OcamlStandardMapCarrierContract.declarationParameters(type);
	if (mapParameters != null) {
		for (parameter in mapParameters)
			if (declarationCarrier(parameter, representations, nominalType, context) == null)
				return null;
		// The existing map owner classifies source identity and seals the runtime
		// reference. Neither a printed name nor generic class shape is sufficient.
		return switch (nominalType(type)) {
			case carrier = TRuntimeApp(_, parameters) if (parameters.length == mapParameters.length): carrier;
			case _: null;
		};
	}
	return switch (type) {
		case TFun(parameters, result):
			final projectedResult = declarationCarrier(result, representations, nominalType, context);
			if (projectedResult == null) {
				null;
			} else {
				var functionType = projectedResult;
				for (index in 0...parameters.length) {
					final parameter = parameters[parameters.length - 1 - index];
					// The optional flag does not imply a Null<T> wrapper in typed
					// function syntax. String keeps one carrier for present and absent
					// values; do not infer that property for scalars or enum variants.
					if (parameter.opt && !isStringCallbackArgument(parameter.t))
						return null;
					final parameterType = declarationCarrier(parameter.t, representations, nominalType, context);
					if (parameterType == null)
						return null;
					functionType = TArrow(parameterType, functionType);
				}
				parameters.length == 0 ? TArrow(TIdent("unit"), functionType) : functionType;
			}
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
		case TAbstract(reference, [inner]) if (reference.get().pack.length == 0 && reference.get().name == "Null"):
			if (OcamlStandardMapCarrierContract.declarationParameters(TypeTools.follow(inner)) != null) {
				// Null<Map<K,V>> can be boxed even when Map<K,V> uses HxMap.
				// Validate the element contract, then preserve the actual nullable
				// storage instead of inferring it from the non-null map carrier.
				if (declarationCarrier(inner, representations, nominalType, context) == null) {
					null;
				} else {
					switch (nominalType(type)) {
						case carrier = TIdent("Obj.t"): carrier;
						case carrier = TRuntimeApp(_, _): carrier;
						case _: null;
					}
				}
			} else {
				// Other supported references retain their existing null sentinel.
				// Nullable enums instead preserve their existing boxed null-or-variant carrier.
				switch (TypeTools.follow(inner)) {
					case referred = TInst(_, _): declarationCarrier(referred, representations, nominalType, context);
					case referred = TEnum(_, _):
						if (declarationCarrier(referred, representations, nominalType, context) == null) {
							null;
						} else {
							switch (nominalType(type)) {
								case carrier = TIdent("Obj.t"): carrier;
								case _: null;
							}
						}
					case _: null;
				}
			}
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
						&& (OcamlMonomorphicClassPlanner.hasDirectRecordLayout(definition, context)
							|| hasInheritedDeclarationRecord(definition, context))): nominalType(type);
				case _: null;
			}
		case TEnum(reference, []) if (!reference.get().isExtern && reference.get().params.length == 0):
			// Ordinary enum declarations already own a named OCaml variant. The
			// result optimization catalog is not the authority for that public type.
			nominalType(type);
		case _: null;
	}
}

/**
	Recognizes ordinary class records selected by the complete inheritance scan.

	Class emission owns the base-prefix layout and method slots. Exporting that
	named type does not permit direct-field optimizations or alter upcasts. Every
	ancestor must use ordinary non-generic class emission; foreign and specialized
	layouts need their own declaration contract.
**/
function hasInheritedDeclarationRecord(definition:ClassType, context:CompilationContext):Bool {
	if (!context.virtualTypesComputed || !context.dispatchTypes.exists(definition.pack.concat([definition.name]).join(".")))
		return false;
	var current:Null<ClassType> = definition;
	while (current != null) {
		if (current.isExtern
			|| current.isInterface
			|| current.params.length > 0
			|| current.meta.has(":native")
			|| current.interfaces.length > 0
			|| (current.pack.length > 0 && current.pack[0] == "ocaml"))
			return false;
		switch (current.kind) {
			case KNormal:
			case _:
				return false;
		}
		for (field in current.fields.get()) {
			if (field.meta.has(":native"))
				return false;
			switch (field.kind) {
				case FMethod(MethDynamic):
					return false;
				case _:
			}
		}
		current = current.superClass == null ? null : current.superClass.t.get();
	}
	return true;
}

/** Optional String calls and their declarations share the same null sentinel. */
private function isStringCallbackArgument(type:Type):Bool {
	return switch (TypeTools.follow(type)) {
		case TInst(reference, []): final definition = reference.get(); definition.pack.length == 0 && definition.module == "String" && definition.name == "String";
		case _: false;
	};
}

/** Recognizes the source Array declaration; checked storage still comes from its owner. */
private function isStandardArray(type:Type):Bool {
	return switch (type) {
		case TInst(reference, [_]): final definition = reference.get(); definition.pack.length == 0 && definition.module == "Array" && definition.name == "Array";
		case _: false;
	};
}
#end
