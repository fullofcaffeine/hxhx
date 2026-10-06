package backend.cpp;

/**
	Emit immutable native enum metadata from exact typed declaration facts.
	Singleton startup uses these descriptors before class initialization. Payload
	constructor calls, conversion, and source equality remain separate Haxe decisions.
 */
class CppManagedEnumDescriptors {
	final program:CppTypedProgramProjection;
	final owners:Array<TypedBackendClassProjection> = [];
	final symbols = new haxe.ds.ObjectMap<TypedBackendClassProjection, String>();

	public function new(program:CppTypedProgramProjection) {
		if (program == null)
			throw "enum descriptors require an exact program";
		this.program = program;
		program.assertCurrent();
		for (module in program.getModules())
			for (owner in module.projection.getClasses())
				switch owner.requireSemanticFacts().getNominalKind() {
					case EnumValue:
						owners.push(owner);
					case _:
				}
		owners.sort((left, right) -> {
			final a = left.requireSemanticFacts().getClassIdentity();
			final b = right.requireSemanticFacts().getClassIdentity();
			return a < b ? -1 : a > b ? 1 : 0;
		});
		for (index in 0...owners.length)
			symbols.set(owners[index], "hxhx_enum_" + index);
	}

	/**
		Select only enums whose every constructor is parameterless. Their exact
		descriptor and ordinal fully identify a key; payloads need structural comparison.
		Other nominal categories return no match instead of borrowing enum storage.
	 */
	public function findNullarySymbol(type:TyType):Null<String> {
		program.assertCurrent();
		CppManagedClosureAbi.assertComplete(type);
		final identity = type.getNominalIdentity();
		if (identity == null)
			return null;
		final owner = program.requireClass(program.requireClassIdentity(identity.getCanonicalName()));
		final facts = owner.requireSemanticFacts();
		switch facts.getNominalKind() {
			case EnumValue:
			case _:
				return null;
		}
		if (facts.getIsExtern() || type.getTypeArguments().length != 0 || facts.getTypeParameterIds().length != 0)
			throw 'managed enum Map keys require an ordinary nongeneric enum';
		for (constructor in facts.copyEnumConstructors())
			switch constructor.member {
				case Singleton(_):
				case Callable(_):
					throw 'managed enum Map keys require structural payload comparison';
			}
		return requireSymbol(owner);
	}

	/** A same-named class from another projection cannot borrow this program's symbol. */
	public function requireSymbol(owner:TypedBackendClassProjection):String {
		program.assertCurrent();
		final symbol = symbols.get(owner);
		if (symbol == null)
			throw "enum descriptor requires its exact program-owned enum";
		return symbol;
	}

	/**
		Allocate each parameterless constructor once per heap before class startup.
		The temporary root protects publication; static cells retain earlier singletons
		when a later allocation collects. No synthetic initializer record is executed.
	 */
	public function renderSingletonStartup(statics:CppManagedStaticStorage, heap:String, destination:String):Array<String> {
		program.assertCurrent();
		if (!~/^[A-Za-z_][A-Za-z0-9_]*$/.match(heap) || !~/^[A-Za-z_][A-Za-z0-9_]*$/.match(destination))
			throw "managed enum startup requires allocated native symbols";
		final lines = new Array<String>();
		for (owner in owners) {
			if (owner.requireSemanticFacts().getIsExtern())
				continue;
			for (constructor in owner.requireSemanticFacts().copyEnumConstructors())
				switch constructor.member {
					case Singleton(_):
						final member = statics.singletonMember(owner, constructor.index);
						lines.push("{");
						lines.push("  hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::EnumPayload>> hxhx_singleton(" + heap + ");");
						lines.push("  " + heap + ".allocateInto(hxhx_singleton, " + symbols.get(owner) + ", " + constructor.index
							+ ", std::vector<hxhx::managed::Value>{});");
						lines.push("  " + destination + ".get()->" + member + ".write(hxhx::managed::Value::managed(hxhx_singleton.get()));");
						lines.push("}");
					case Callable(_):
				}
		}
		return lines;
	}

	/** The caller includes ManagedValue.hpp before these static-lifetime declarations. */
	public function render():String {
		program.assertCurrent();
		final lines = new Array<String>();
		for (owner in owners) {
			final symbol = symbols.get(owner);
			final facts = owner.requireSemanticFacts();
			final constructors = facts.copyEnumConstructors();
			if (constructors.length > 0) {
				lines.push("inline const hxhx::managed::EnumConstructorDescriptor " + symbol + "_constructors[] = {");
				for (constructor in constructors) {
					final arity = switch constructor.member {
						case Singleton(_): 0;
						case Callable(method): method.arguments.length;
					};
					lines.push("  {" + CppManagedText.quotedBytes(constructor.name) + ", " + arity + "},");
				}
				lines.push("};");
			}
			lines.push("inline const hxhx::managed::EnumDescriptor "
				+ symbol
				+ " = {"
				+ CppManagedText.quotedBytes(facts.getClassIdentity())
				+ ", "
				+ (constructors.length == 0 ? "nullptr" : symbol + "_constructors")
				+ ", "
				+ constructors.length
				+ "};");
		}
		return lines.join("\n");
	}
}
