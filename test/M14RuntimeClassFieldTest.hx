/** Undeclared fields belong to the current runtime class value, not a static declaration. */
class M14RuntimeClassFieldTest {
	/** Real module paths distinguish selected static declarations from runtime object properties. */
	static function assertProjection():Void {
		final entries = [
			{name: "foreign.Holder", source: "package foreign; class Holder {public static var value:Int=7;}"},
			{
				name: "Main",
				source: 'import foreign.Holder as Alias;
class Main {
static function declared():Int {return foreign.Holder.value;}
static function uncheckedDeclared():Int {return untyped foreign.Holder.value;}
static function extra():Dynamic {return untyped foreign.Holder.extra;}
static function aliasExtra():Dynamic {return untyped Alias.extra;}
static function shadow(foreign:{Holder:{value:Int}}):Int {return foreign.Holder.value;}
}'
			}
		];
		final modules = [
			for (entry in entries) {
				final path = entry.name.split(".").join("/") + ".hx";
				new ResolvedModule(entry.name, path, ParserStage.parse(entry.source, path));
			}
		];
		final index = TyperIndex.buildHeaders(modules);
		final loader = new ModuleLoader(["."], HxDefineMap.fromRawDefines([]), index, _ -> false);
		loader.markResolvedAlready(modules);
		final typed = [for (module in modules) TyperStage.typeResolvedModule(module, index, loader)];
		for (owner in typed[1].getBackendProjection().getClasses())
			for (body in owner.getFunctions()) {
				final name = HxFunctionDecl.getName(body.getDeclaration());
				final runtime = body.getRuntimeTypeCatalog().getEntries();
				final dynamicField = name == "extra" || name == "aliasExtra";
				if (runtime.length != (dynamicField ? 1 : 0))
					throw "field projection lost the value/declaration boundary: " + name;
				if (dynamicField && runtime[0].getTarget().getSemanticKey() != "runtime-nominal:foreign.Holder")
					throw "runtime field receiver lost its exact class identity";
				var selected = false;
				for (statement in body.getBody())
					TypedBackendSourceWalk.statement(statement, expression -> {
						final field = body.findField(expression);
						if (field != null) {
							if (field.getField().getCanonicalKey() != "foreign.Holder#static#value")
								throw "declared static field changed owner";
							selected = true;
						}
					}, _ -> {});
				if (selected != (name == "declared" || name == "uncheckedDeclared"))
					throw "field projection confused a declaration with a dynamic property: " + name;
			}
		Sys.println("RUNTIME_CLASS_FIELD_PROJECTION:PASS");
	}

	static function main():Void {
		assertProjection();
		final jsSource = 'class Holder {} class Main {static function main():Void {
untyped Holder.value=7; Sys.println(untyped Holder.value);
untyped Holder.value=9; Sys.println(untyped Holder.value);
}}';
		@:privateAccess M14JsRuntimeTypeOperandsTest.assertUpstreamJs(jsSource, "7\n9\n");
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(jsSource, "Main.hx"));
		JsRuntimeFixture.assertRuntime(TyperStage.typeResolvedModule(module, TyperIndex.build([module])), "Main", "7\n9\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("runtime_class_field", 'class Holder {}
class Main {
static function main():Void {
untyped Holder.value = 7;
Sys.println(untyped Holder.value);
var original:Dynamic = Holder;
var replacement:Dynamic = {value:9};
untyped Holder = replacement;
Sys.println(untyped Holder.value);
untyped Holder = original;
Sys.println(untyped Holder.value);
}
}', "7\n9\n7\n");
	}
}
