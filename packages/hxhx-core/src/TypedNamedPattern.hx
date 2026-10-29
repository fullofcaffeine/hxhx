/** The declaration selected by a named pattern, before target representation is chosen. */
enum TypedNamedPatternKind {
	Constructor(owner:TyNominalTypeId, name:String, index:Int, arity:Int);
	Constant(field:TyFieldInfo);
}

/**
	Keep enum constructors distinct from enum-abstract constants.

	An ordinary enum constructor identifies one member of one declaration. An
	enum-abstract constant retains the resolved field and its primitive value.
	Targets consume these facts instead of inferring meaning from a case label.
 */
class TypedNamedPattern {
	final kind:TypedNamedPatternKind;

	public function new(kind:TypedNamedPatternKind) {
		this.kind = kind;
	}

	public function getKind():TypedNamedPatternKind
		return kind;

	public function getSemanticKey():String {
		return CompilerCacheIdentity.encode(switch kind {
			case Constructor(owner, name, index, arity):
				[
					"enum-constructor",
					owner.getCanonicalName(),
					name,
					Std.string(index),
					Std.string(arity)
				];
			case Constant(field):
				[
					"enum-constant",
					field.getCanonicalKey(),
					field.getConstant().getCanonicalIdentity()
				];
		});
	}
}
