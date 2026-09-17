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
			case ArrayCore | StringCore | IntCore | FloatCore | BoolCore:
		}
		this.kind = kind;
		this.sourceSpelling = sourceSpelling == null || sourceSpelling.length == 0 ? switch (kind) {
			case IntCore: "Int";
			case FloatCore: "Float";
			case BoolCore: "Bool";
			case _: requireDeclarationIdentity().getCanonicalName();
		} : sourceSpelling;
	}

	public function getKind():TypedRuntimeTypeKind
		return kind;

	/** Primitive type objects have no class declaration; Array and String retain their real providers. */
	public function getDeclarationIdentity():Null<TyNominalTypeId>
		return switch (kind) {
			case Nominal(identity): identity;
			case ArrayCore: new TyNominalTypeId("Array");
			case StringCore: new TyNominalTypeId("String");
			case IntCore | FloatCore | BoolCore: null;
		};

	/** Require a real declaration at operations that cannot handle a primitive type object. */
	public function requireDeclarationIdentity():TyNominalTypeId {
		final identity = getDeclarationIdentity();
		if (identity == null)
			throw "runtime type target has no declaration owner: " + getSemanticKey();
		return identity;
	}

	/** Presentation only: preserve source qualifiers without using them to select a type. */
	public function getSourceSpelling():String
		return sourceSpelling;

	public function getInstanceType():TyType
		return switch (kind) {
			case Nominal(identity): TyType.nominal(identity, []);
			// A runtime Array class object erases its element type, as Class<Array<Dynamic>> does in Haxe.
			case ArrayCore: TyType.nominal(requireDeclarationIdentity(), [TyType.fromHintText("Dynamic")]);
			case StringCore: TyType.fromHintText("String");
			case IntCore: TyType.fromHintText("Int");
			case FloatCore: TyType.fromHintText("Float");
			case BoolCore: TyType.fromHintText("Bool");
		};

	/** Runtime primitive abstract values have Abstract<T>; class and interface values have Class<T>. */
	public function getValueType():TyType
		return switch (kind) {
			case IntCore | FloatCore | BoolCore: TyType.abstractMeta(getInstanceType());
			case _: TyType.nominal(new TyNominalTypeId("Class"), [getInstanceType()]);
		};

	public function getSemanticKey():String
		return switch (kind) {
			case Nominal(identity): "runtime-nominal:" + identity.getCanonicalName();
			case ArrayCore: "runtime-core:Array";
			case StringCore: "runtime-core:String";
			case IntCore: "runtime-core:Int";
			case FloatCore: "runtime-core:Float";
			case BoolCore: "runtime-core:Bool";
		};
}
