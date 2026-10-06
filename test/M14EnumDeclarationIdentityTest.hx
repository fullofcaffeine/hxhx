/** Enum identity and constructor order must survive parsing, typing, projection, and revision calculation. */
class M14EnumDeclarationIdentityTest {
	static function typed(source:String):TypedModule {
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
	}

	static function main():Void {
		final prefix = "class Main { static function main():Void {} } class Pretender { public static var __hx_is_enum:Bool = true; } ";
		final first = typed(prefix + "enum Choice<T> { Last; Carry(value:T); First; }");
		final second = typed(prefix + "enum Choice<T> { First; Carry(value:T); Last; }");
		var sawEnum = false;
		var sawPretender = false;
		for (owner in first.getBackendProjection().getClasses()) {
			final facts = owner.requireSemanticFacts();
			final declaration = HxClassDecl.getEnumDeclaration(owner.getDeclaration());
			if (facts.getClassIdentity() == "Main.Pretender") {
				sawPretender = true;
				if (declaration != null || facts.getNominalKind() != ClassInstance)
					throw "ordinary field spelling forged enum identity";
			}
			if (facts.getClassIdentity() == "Main.Choice") {
				sawEnum = true;
				if (declaration == null || facts.getNominalKind() != EnumValue)
					throw "enum identity disappeared through projection";
				final entries = declaration.getConstructors();
				if ([for (entry in entries) entry.name + ":" + entry.arity].join(",") != "Last:0,Carry:1,First:0")
					throw "enum declaration lost source order or constructor arity";
				entries.reverse();
				entries.pop();
				if (declaration.getConstructors().length != 3 || declaration.getConstructors()[0].name != "Last")
					throw "consumer changed parsed enum constructor order";
				final constructors = facts.copyEnumConstructors();
				if (constructors.length != 3 || constructors[0].index != 0 || constructors[1].index != 1 || constructors[2].index != 2)
					throw "typed constructor tags lost source order";
				switch constructors[0].member {
					case Singleton(field):
						if (field.canonicalIdentity != "Main.Choice#static#Last")
							throw "singleton lost its exact field identity";
					case _:
						throw "nullary constructor became a callable";
				}
				switch constructors[1].member {
					case Callable(method):
						if (method.arguments.length != 1
							|| !method.arguments[0].semanticType.isTypeParameter()
							|| !method.isEnumConstructor
							|| method.returnSemanticType.getNominalIdentity().getCanonicalName() != "Main.Choice")
							throw "payload constructor lost its exact signature";
						final key = method.arguments[0].semanticType.getSemanticKey();
						method.arguments.pop();
						switch facts.copyEnumConstructors()[1].member {
							case Callable(retained):
								if (retained.arguments.length != 1
									|| retained.arguments[0].semanticType.getSemanticKey() != key) throw "consumer mutated the retained constructor signature";
							case _: throw "constructor kind changed";
						}
					case _:
						throw "payload constructor became a singleton";
				}
			}
		}
		if (!sawEnum || !sawPretender)
			throw "enum identity fixture lost a declaration";
		final primary = typed("enum Main { Empty; Value(value:Int); }");
		final primaryFacts = primary.getBackendProjection().getClasses()[0].requireSemanticFacts();
		if (primaryFacts.getNominalKind() != EnumValue || primaryFacts.copyEnumConstructors().length != 2)
			throw "primary module enum lost its declaration inventory";
		if (CompilerTypedModuleRevision.fromTypedModule(first)
			.publicInterfaceRevision == CompilerTypedModuleRevision.fromTypedModule(second)
			.publicInterfaceRevision)
			throw "constructor reorder did not invalidate the public enum contract";
		Sys.println("ENUM_DECLARATION_IDENTITY:PASS");
	}
}
