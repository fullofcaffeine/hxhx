import sys.io.File;

/** Observe instance field effects and callable storage across declared and inherited constructors. */
class M14Stage3InstanceInitializersTest {
	/** Field helpers reject foreign projections and stale bodies, and preserve their ordered inventory. */
	static function ownership():Void {
		final source = 'class Main { public var value:Int = { var local=3; local; }; public function new() {} static function __hx_initialize_instance_fields():Void {} }';
		function project():TypedBackendClassProjection {
			final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
			return TyperStage.typeResolvedModule(module, TyperIndex.build([module])).getBackendProjection().getClasses()[0];
		}
		final owner = project();
		final storage = new backend.ocaml.Stage3OcamlClassStorage();
		storage.add(owner, false, "Main");
		final plan = storage.instanceInitializers(owner);
		if (plan == null || plan.getName() == "__hx_initialize_instance_fields")
			throw "initializer helper collided with an authored method";
		function rejected(action:Void->Void, fragment:String):Void {
			try {
				action();
			} catch (error:String) {
				if (error.indexOf(fragment) >= 0)
					return;
				throw error;
			}
			throw "initializer ownership check accepted invalid evidence";
		}
		rejected(() -> storage.instanceInitializers(project()), "exact class projection");
		final fields = plan.getFields();
		fields.resize(0);
		if (plan.getFields().length != 1)
			throw "caller changed initializer inventory";
		switch plan.getFields()[0].getExpression() {
			case ELoweredControl(_, _, entries, _):
				entries.push(EInt(99));
			case _:
				throw "initializer ownership fixture lost its lowered block";
		}
		rejected(() -> plan.getFields(), "projection was mutated");
	}

	static function main():Void {
		ownership();
		final root = "test/fixtures/stage3_instance_initializers";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		final typed = M14Stage3RuntimeFixture.typeMain({source: File.getContent(path), path: path, root: root});
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), ".tmp/stage3_instance_initializers");
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("STAGE3_INSTANCE_INITIALIZERS:PASS");
	}
}
