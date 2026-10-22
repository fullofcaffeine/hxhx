import sys.io.File;

/** Compare actual constructor effects and object state with upstream Haxe. */
class M14Stage3ConstructorExecutionTest {
	/** Equal source text cannot borrow another program's constructor declaration. */
	static function ownership():Void {
		final source = "class Main { public function new(value:Int) {} static function main() { new Main(1); } }";
		function projection():TypedBackendClassProjection {
			final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
			return TyperStage.typeResolvedModule(module, TyperIndex.build([module])).getBackendProjection().getClasses()[0];
		}
		final owner = projection();
		final foreign = projection();
		final storage = new backend.ocaml.Stage3OcamlClassStorage();
		storage.add(owner, false, "Main");
		function render(cls:TypedBackendClassProjection):String {
			final method = cls.getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == "main")[0];
			final expression = TypedConstructorSource.inFunction(method.getDeclaration())[0];
			return storage.construct({
				occurrence: method.requireConstructor(expression),
				currentModule: "Main",
				names: new backend.ocaml.Stage3OcamlLocalNames(method.getLocalCatalog(), false, value -> value),
				emitArgument: (_, _, _) -> "1",
				quote: value -> '"' + value + '"'
			});
		}
		if (render(owner).indexOf("new_") < 0)
			throw "owned constructor was not selected";
		var rejected = false;
		try {
			render(foreign);
		} catch (error:String) {
			rejected = error.indexOf("exact declaration") >= 0;
		}
		if (!rejected)
			throw "construction accepted a separately typed declaration";
	}

	static function main():Void {
		ownership();
		final root = "test/fixtures/stage3_constructor_execution";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		final typed = M14Stage3RuntimeFixture.typeMain({source: File.getContent(path), path: path, root: root});
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), ".tmp/stage3_constructor_execution", true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("STAGE3_CONSTRUCTOR_EXECUTION:PASS");
	}
}
