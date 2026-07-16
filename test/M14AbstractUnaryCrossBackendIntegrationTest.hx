import backend.BackendContext;
import backend.BackendRegistry;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Proves two non-C++ backends execute the same shared unary declaration decision. **/
class M14AbstractUnaryCrossBackendIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function run(command:String, path:String):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, [path]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function main():Void {
		final source = [
			"abstract Step(Int) from Int to Int {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(-A) public static function arbitraryStaticResult(value:Step):Int return 11;",
			"  @:op(++A) public static function propertyMustNotCall(value:Step):Step return value;",
			"  public function get():Int return this;",
			"}",
			"class Holder {",
			"  public var getterCalls:Int = 0;",
			"  public var setterCalls:Int = 0;",
			"  var stored:Step;",
			"  public var step(get, set):Step;",
			"  public function new(value:Int) stored = value;",
			"  public function get_step():Step { getterCalls++; return stored; }",
			"  public function set_step(value:Step):Step { setterCalls++; stored = value; return value; }",
			"  public function value():Step return stored;",
			"}",
			"class Main { static function main() {",
			"  var step:Step = 1;",
			"  Sys.println(-step);",
			"  var ordinary = 3;",
			"  Sys.println(-ordinary);",
			"  var holder = new Holder(4);",
			"  var before:Step = ++holder.step;",
			"  var after:Step = holder.step++;",
			"  Sys.println(before);",
			"  Sys.println(after);",
			"  Sys.println(holder.value());",
			"  Sys.println(holder.getterCalls);",
			"  Sys.println(holder.setterCalls);",
			"} }",
		].join("\n");
		final parsed = ParserStage.parse(source, "Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(["."], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index, loader);
		final program = new MacroExpandedProgram([typed], false);

		final root = Path.join([Sys.getCwd(), ".tmp", "m14_abstract_unary_cross_backend"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final cases = [
			{
				target: "js-native",
				executable: "node",
				fileName: "out.js",
				callText: "__hx_cls_Step.arbitraryStaticResult(step)"
			},
			{
				target: "python-native",
				executable: "python3",
				fileName: "out.py",
				callText: "Step.arbitraryStaticResult(step)"
			},
		];
		for (entry in cases) {
			final outputPath = Path.join([root, entry.fileName]);
			final context = new BackendContext(Path.join([root, entry.target]), outputPath, "Main", true, false, new StringMap<String>());
			final emitted = BackendRegistry.createForTarget(entry.target).emit(program, context);
			final generated = File.getContent(emitted.entryPath);
			assertTrue(generated.indexOf(entry.callText) >= 0, entry.target + " rebound or lost the arbitrary-name helper selected by the shared typer");
			final executed = run(entry.executable, emitted.entryPath);
			assertTrue(executed.code == 0, entry.target + " abstract-unary artifact failed: " + executed.stderr);
			assertTrue(executed.stdout == "11\n-3\n5\n5\n6\n2\n2\n",
				entry.target + " produced unexpected abstract/property/ordinary unary output: " + executed.stdout);
		}
		deleteRecursive(root);
	}
}
