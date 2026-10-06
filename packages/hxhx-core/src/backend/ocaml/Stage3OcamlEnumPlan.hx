package backend.ocaml;

/** Closed storage choices for native enum payloads; enum values retain their runtime box. */
enum Stage3OcamlEnumPayload {
	NativeInt;
	NativeBool;
	NativeString;
	EnumBox(owner:String);
}

typedef Stage3OcamlEnumConstructor = {
	final index:Int;
	final name:String;
	final declaration:String;
	final targetName:String;
	final payloads:Array<Stage3OcamlEnumPayload>;
};

/**
	Copies exact compiler declarations into the native enum representation plan.

	This is the Stage3 enum boundary for reading semantic facts. The resulting
	plan retains only target-owned storage choices, names, and declaration keys.
	It keeps Haxe constructor indexes separate from OCaml tags. Named payloads
	must subsequently resolve to another enum in the same request before rendering.
**/
class Stage3OcamlEnumPlan {
	public final owner:String;
	public final moduleIdentity:String;
	public final runtimeName:String;
	public final outputModule:String;
	public final constructors:Array<Stage3OcamlEnumConstructor>;

	function new(owner:String, moduleIdentity:String, runtimeName:String, outputModule:String, constructors:Array<Stage3OcamlEnumConstructor>) {
		this.owner = owner;
		this.moduleIdentity = moduleIdentity;
		this.runtimeName = runtimeName;
		this.outputModule = outputModule;
		this.constructors = constructors;
	}

	/** Ordinary classes return null; only parser and typer agreement admits an enum. */
	public static function fromProjection(projection:TypedBackendClassProjection, outputModule:String, packagePath:String,
			valueName:String->String):Null<Stage3OcamlEnumPlan> {
		final declaration = projection.getDeclaration();
		if (HxClassDecl.getEnumDeclaration(declaration) == null)
			return null;
		final facts = projection.requireSemanticFacts();
		switch (facts.getNominalKind()) {
			case EnumValue:
			case _:
				throw "OCaml enum declaration has a non-enum semantic owner";
		}
		if (facts.getIsExtern() || HxClassDecl.getIsExtern(declaration) || facts.getTypeParameters().length != 0)
			throw "OCaml enum representation is not implemented for extern or generic enum " + facts.getClassIdentity();
		final constructors:Array<Stage3OcamlEnumConstructor> = [];
		final names:Map<String, Bool> = new Map();
		for (constructor in facts.copyEnumConstructors()) {
			final targetName = valueName(constructor.name);
			if (names.exists(targetName))
				throw "OCaml enum constructor name collision: " + facts.getClassIdentity() + "." + constructor.name;
			names.set(targetName, true);
			final member = switch (constructor.member) {
				case Singleton(field): {identity: field.canonicalIdentity, payloads: []};
				case Callable(method):
					final payloads = [
						for (argument in method.arguments) {
							if (argument.isOptional || argument.isRest) throw "OCaml enum optional/rest payload is not implemented: "
								+ method.canonicalIdentity;
							payload(argument.semanticType, method.canonicalIdentity);
						}
					];
					{identity: method.canonicalIdentity, payloads: payloads};
			};
			constructors.push({
				index: constructor.index,
				name: constructor.name,
				declaration: member.identity,
				targetName: targetName,
				payloads: member.payloads
			});
		}
		final name = HxClassDecl.getName(declaration);
		return new Stage3OcamlEnumPlan(facts.getClassIdentity(), facts.getModuleIdentity(), packagePath.length == 0 ? name : packagePath + "." + name,
			outputModule, constructors);
	}

	static function payload(type:TyType, declaration:String):Stage3OcamlEnumPayload {
		if (type.getSemanticKey() == TyType.fromHintText("Int").getSemanticKey())
			return NativeInt;
		if (type.getSemanticKey() == TyType.fromHintText("Bool").getSemanticKey())
			return NativeBool;
		if (type.getSemanticKey() == TyType.fromHintText("String").getSemanticKey())
			return NativeString;
		final inner = type.unwrapNull();
		final nominal = inner.getNominalIdentity();
		// Both nullable and non-null enum values use HxEnum's existing boxed boundary.
		// The request catalog must prove this exact nominal owner is an enum.
		if (nominal != null && inner.getTypeArguments().length == 0)
			return EnumBox(nominal.getCanonicalName());
		throw "OCaml enum payload representation is not implemented: " + declaration + " / " + type.getDisplay();
	}
}
