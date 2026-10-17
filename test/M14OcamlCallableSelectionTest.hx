import backend.ocaml.Stage3OcamlCallableSelection.select;

/** Native typed bodies must identify every caller before shared callback interfaces can change. */
class M14OcamlCallableSelectionTest {
	static function typed(source:String):TypedModule {
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
	}

	static function expect(module:TypedModule, expected:Array<String>):Void {
		final before = CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity();
		final actual = select([module]).map(method -> method.fieldName);
		actual.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		if (actual.join(",") != expected.join(","))
			throw "Native callback selection: expected " + expected.join(",") + ", got " + actual.join(",");
		if (CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity() != before)
			throw "Callback selection changed typed source";
	}

	static function main():Void {
		expect(typed(sys.io.File.getContent("test/fixtures/stage3_stored_callback_views/Main.hx")), [
			"captured",
			"forwarded",
			"literal",
			"main",
			"preserve",
			"relay",
			"staticCallback"
		]);
		final factory = "static function factory():Int->Int return value -> value + 1;";
		final consumer = "static function main():Void { var callback = factory(); callback(7); }";
		expect(typed("class Main {" + factory + consumer + "}"), ["factory", "main"]);
		for (observer in [
			"static var escaped:Dynamic = factory();",
			"public function new() { var callback = factory(); callback(7); }",
			"static function __init__():Void { var callback = factory(); callback(7); }",
			"static function escape():Dynamic return factory();",
			"static function contain():Void { var callbacks = [factory()]; }",
			"static function mutate():Void { var callback = factory(); callback = factory(); }",
			"static function capture():Void { var callback = factory(); var nested = () -> callback(7); }",
			"static function unchecked():Void { var callback:String->String = cast factory(); callback('x'); }",
			"static function recursive():Void { var callback = factory(); var self = function again(value:Int):Int return value < 1 ? callback(0) : again(value - 1); }",
			"static function reflect():Void { var owner = Main; var method = Reflect.field(owner, 'factory'); }"
		])
			expect(typed("class Main {" + factory + consumer + observer + "}"), []);
		// Secondary classes can observe a method even when its ordinary caller appears first.
		expect(typed("class Main { static function main():Void { var callback = Provider.factory(); callback(7); } }"
			+ "class Provider { public static function factory():Int->Int return value -> value + 1; }"
			+ "class Observer { static var escaped:Dynamic = Provider.factory(); }"),
			[]);
		Sys.println("NATIVE_OCAML_CALLABLE_SELECTION:PASS");
	}
}
