/** Real C++ providers must supply exact catch facts before backend reachability is selected. */
class M14CppCatchUseTest {
	public static function run():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/cpp_catch_binding_seed",
			mainModule: "Main",
			requiredModules: ["haxe.Exception", "haxe.ValueException"]
		});
		final functions = fixture.main.getTypedClasses()[0].getFunctions();
		final main = functions.filter(fn -> fn.getStableIdentity().indexOf("#static:main(") >= 0);
		if (main.length != 1)
			throw "catch fixture requires one exact main";
		final projection = TypedBodySource.functionProjection(main[0]);
		final catalog = projection.getLocalCatalog();
		final locals = catalog.getEntries().filter(local -> local.getBinding().getKind() == CatchVariable);
		if (locals.length != 6)
			throw "catch fixture lost its exact handler bindings";
		for (local in locals) {
			final binding = local.getBinding();
			final use = catalog.findCatchUse(binding.getIdentity().getCanonicalKey());
			if (use == null || use.binding.getCanonicalIdentity() != binding.getCanonicalIdentity())
				throw "C++ catch lacks its exact implicit provider use: " + binding.getSourceName();
			switch binding.getSourceName() {
				case "number" | "text":
					final expected = binding.getSourceName() == "number" ? "IntCore" : "StringCore";
					if (use.view != OrdinaryValue
						|| use.target == null
						|| Type.enumConstructor(use.target.getKind()) != expected
						|| use.payload == null
						|| use.payload.getOwner().getCanonicalName() != "haxe.ValueException"
						|| use.conversion != null)
						throw "ordinary catch lost its typed target or exact payload field";
				case "any" | "fallback":
					if (use.view != Carrier || use.target != null || use.payload != null || use.conversion != null)
						throw "Dynamic catch must preserve the incoming carrier";
				case "wrapped":
					if (use.view != ExceptionSubtype
						|| use.target == null
						|| use.target.requireDeclarationIdentity().getCanonicalName() != "haxe.ValueException"
						|| use.conversion != null
						|| use.payload != null)
						throw "explicit wrapper catch must not allocate an implicit wrapper";
				case "exception":
					if (use.view != BaseException
						|| use.conversion == null
						|| use.conversion.getOwner().getCanonicalName() != "haxe.Exception"
						|| use.conversion.getSignature().getName() != "caught"
						|| use.target != null
						|| use.payload != null)
						throw "default catch lost its real conversion declaration";
				case _:
					throw "unexpected catch binding";
			}
		}
		Sys.println("CPP_CATCH_USES:PASS");
	}

	static function main():Void
		run();
}
