/**
	An exact runtime target selected by shared typing.

	Nominal classes and interfaces retain their declaration identity. Admitted
	core types have separate variants, so targets never infer their runtime
	representation from a display name. Source spelling serves projection only.
**/
class TypedRuntimeTypeTarget {
	final kind:TypedRuntimeTypeKind;
	final sourceSpelling:String;

	public function new(kind:TypedRuntimeTypeKind, ?sourceSpelling:String) {
		if (kind == null)
			throw "runtime type target requires an admitted kind";
		switch (kind) {
			case Nominal(identity):
				if (identity == null || identity.getCanonicalName().length == 0)
					throw "runtime type target requires an exact nominal identity";
			case ArrayCore | StringCore:
		}
		this.kind = kind;
		this.sourceSpelling = sourceSpelling == null || sourceSpelling.length == 0 ? getIdentity().getCanonicalName() : sourceSpelling;
	}

	public function getKind():TypedRuntimeTypeKind
		return kind;

	/** Declaration owner for dependency and static-member selection, including core providers. */
	public function getIdentity():TyNominalTypeId
		return switch (kind) {
			case Nominal(identity): identity;
			case ArrayCore: new TyNominalTypeId("Array");
			case StringCore: new TyNominalTypeId("String");
		};

	/** Presentation only: preserve source qualifiers without using them to select a type. */
	public function getSourceSpelling():String
		return sourceSpelling;

	public function getInstanceType():TyType
		return switch (kind) {
			case Nominal(identity): TyType.nominal(identity, []);
			// A runtime Array class object erases its element type, as Class<Array<Dynamic>> does in Haxe.
			case ArrayCore: TyType.nominal(getIdentity(), [TyType.fromHintText("Dynamic")]);
			case StringCore: TyType.fromHintText("String");
		};

	/** A class value has a meta-type, distinct from instances of the selected class. */
	public function getValueType():TyType
		return TyType.nominal(new TyNominalTypeId("Class"), [getInstanceType()]);

	public function getSemanticKey():String
		return switch (kind) {
			case Nominal(identity): "runtime-nominal:" + identity.getCanonicalName();
			case ArrayCore: "runtime-core:Array";
			case StringCore: "runtime-core:String";
		};
}
