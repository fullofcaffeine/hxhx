package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlNormalizedRepresentedArray;

/**
	Recognizes the exact built-in array source shapes understood by current proofs.

	Recognition is not permission to use a target representation. It only turns a
	direct `Array<Int>` or `Array<String>` type into plain names without retaining
	the Haxe `Type` object. Each consumer still owns a narrower admission rule. For
	example, general local and place planning currently accepts only the Int result,
	while the literal producer may accept both proved construction families.
**/
class OcamlDirectArraySourceIdentity {
	/** Returns one closed, flat direct-array identity, or null for every wrapper and unsupported element family. */
	public static function normalize(type:Type):Null<OcamlNormalizedRepresentedArray> {
		return switch (type) {
			case TInst(classRef, [elementType]):
				final classType = classRef.get();
				final elementSemanticTypeId = exactElementSemanticTypeId(elementType);
				if (classType.pack.length == 0 && classType.name == "Array" && elementSemanticTypeId != null) {
					{
						arraySemanticTypeId: 'Array<$elementSemanticTypeId>',
						elementSemanticTypeId: elementSemanticTypeId,
						sourceForm: "direct-builtin-array",
						closureKind: "closed-monomorphic",
						outerWrapperKind: "none",
						nestingKind: "flat"
					};
				} else {
					null;
				}
			case _:
				null;
		};
	}

	/** Checks one element against an identity returned by `normalize` without following typedefs or abstracts. */
	public static function matchesElement(type:Type, semanticTypeId:String):Bool {
		return exactElementSemanticTypeId(type) == semanticTypeId;
	}

	static function exactElementSemanticTypeId(type:Type):Null<String> {
		return switch (type) {
			case TAbstract(abstractRef, parameters): final abstractType = abstractRef.get(); parameters.length == 0 && abstractType.pack.length == 0 && abstractType.name == "Int" ? "Int" : null;
			case TInst(classRef, parameters): final classType = classRef.get(); parameters.length == 0 && classType.pack.length == 0 && classType.name == "String" ? "String" : null;
			case _:
				null;
		};
	}
}
#end
