/** Retain the allocated child separately from the exact applied ancestor constructor. */
class M14InheritedConstructorSelectionTest {
	static function main():Void {
		final root = "test/oracle/inherited_constructor_seed";
		final upstream = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		if (Sys.command(upstream == null ? "node_modules/.bin/haxe" : upstream, ["-cp", root, "-main", "Main", "--interp"]) != 0)
			throw "upstream inherited constructor contract differs";
		final source = sys.io.File.getContent(root + "/Main.hx");
		final program = type(source);
		final explicit = construction(program.typed, "explicit");
		final application = explicit.getConstructorApplication();
		if (application == null
			|| application.getDeclaration().getOwner().getCanonicalName() != "Main.Base"
			|| application.getOwnerType().getNominalIdentity().getCanonicalName() != "Main.Base"
			|| application.getConstructedType().getNominalIdentity().getCanonicalName() != "Main.Child")
			throw "inherited construction lost allocated or declared ownership";
		final forwarded = application.getForwardedTypes();
		if ([for (entry in forwarded) entry.getNominalIdentity().getCanonicalName()].join(",") != "Main.Child,Main.Middle")
			throw "inherited construction lost intermediate initializer owners";
		forwarded.resize(0);
		if (application.getForwardedTypes().length != 2
			|| explicit.withExpressions(explicit.getExpressions()).getConstructorApplication() != application)
			throw "inherited application lost immutable replay identity";
		final defaults = construction(program.typed, "defaults").getConstructorApplication();
		if (defaults == null || !defaults.getCallableSignature().getFunctionType().getFunctionParameters()[0].isOptional)
			throw "inherited constructor lost its optional parameter";
		final generic = construction(program.typed, "generic").getConstructorApplication();
		if (generic == null
			|| generic.getDeclaration().getOwner().getCanonicalName() != "Main.GenericBase"
			|| generic.getConstructedType().getNominalIdentity().getCanonicalName() != "Main.GenericLeaf")
			throw "generic inherited constructor lost declaration ownership";
		final parameter = generic.getParameterTypes()[0];
		if (parameter.getNominalIdentity().getCanonicalName() != "Main.Box"
			|| parameter.getTypeArguments()[0].getSemanticKey() != "primitive:Int"
			|| generic.getOwnerArguments()[0].argument.getSemanticKey() != parameter.getSemanticKey())
			throw "generic ancestor substitution used child binders";
		final owner = program.index.getByFullName("Main.Base");
		reject(() -> new TypedConstructorApplication(owner, application.getDeclaration(), application.getConstructedType()), "exact nominal constructor");
		final path = TypedConstructorPath.select(program.index, application.getConstructedType());
		reject(() -> new TypedConstructorApplication(owner, application.getDeclaration(), TyType.nominal(owner.getIdentity(), []), null, path),
			"another owner or allocated result");
		final shorter = type(StringTools.replace(source, "class Child extends Middle", "class Child extends Base"));
		if (construction(shorter.typed, "explicit").getConstructorApplication().getSemanticKey() == application.getSemanticKey())
			throw "constructor revision ignored an intermediate initializer owner";
		for (entry in [
			'class Main { static function main() { var bad = new Empty(); } } class Empty {}',
			'class Main { static function main() { var bad = new Child(3); } } class Base { public function new(value:Int) {} } class Child extends Base { public function new(value:String) { super(1); } }'
		]) {
			final invalid = type(entry);
			if (construction(invalid.typed, "bad").getConstructorApplication() != null)
				throw "missing or inapplicable nearest constructor acquired a fallback";
		}
		Sys.println("INHERITED_CONSTRUCTOR_SELECTION:PASS");
	}

	static function type(source:String):{typed:TypedModule, index:TyperIndex} {
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final index = TyperIndex.build([module]);
		final typed = TyperStage.typeResolvedModule(module, index);
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				TypedBodyInvariant.assertFunction(fn);
		return {typed: typed, index: index};
	}

	static function construction(module:TypedModule, name:String):TypedExpr {
		for (owner in module.getTypedClasses())
			for (fn in owner.getFunctions())
				for (statement in fn.getBody().getStatements()) {
					if (statement.getNames().length > 0 && statement.getNames()[0] == name) {
						final expressions = statement.getExpressions();
						if (expressions.length == 1 && expressions[0].getTag() == NewValue)
							return expressions[0];
					}
				}
		throw "fixture lost constructor local " + name;
	}

	static function reject(action:Void->Void, message:String):Void {
		try
			action()
		catch (failure:haxe.Exception) {
			if (failure.message.indexOf(message) >= 0)
				return;
			throw failure;
		}
		throw "foreign inherited constructor proof was accepted";
	}
}
