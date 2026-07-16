import backend.BackendContext;
import backend.BackendRegistry;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Proves two non-C++ backends execute one shared binary declaration decision. **/
class M14AbstractBinaryCrossBackendIntegrationTest {
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
			"abstract Token(Int) from Int to Int {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(A + B) public static function mergeArbitrarily(left:Token, right:Token):Int return 15;",
			"  @:commutative @:op(A * B) public static function decorateArbitrarily(value:Token, text:String):String return text + '!';",
			"  @:op(A += B) public static function explicitArbitrarily(value:Token, amount:Int):Int return 106;",
			"  @:op(A - B) public inline function differenceArbitrarily(amount:Int):Int return amount + 16;",
			"  @:commutative @:op(A / B) public function wrapArbitrarily(text:String):String return text + '?';",
			"}",
			"abstract NativeText(String) from String to String {",
			"  public inline function new(value:String) this = value;",
			"  @:op(A + B) public static function appendIntArbitrarily(left:NativeText, right:Int):NativeText;",
			"}",
			"class Main { static function main() {",
			"  var left:Token = new Token(2);",
			"  var right:Token = new Token(3);",
			"  var merged = left + right;",
			"  Sys.println(merged);",
			"  Sys.println('x' * left);",
			"  var explicitResult:Int = (left += 4);",
			"  Sys.println(explicitResult);",
			"  Sys.println(left - 1);",
			"  Sys.println('z' / left);",
			"  Sys.println(2 + 3);",
			"  var nativeText:NativeText = 'value';",
			"  Sys.println(nativeText + 4);",
			"} }",
		].join("\n");
		final parsed = ParserStage.parse(source, "Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(["."], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index, loader);
		final program = new MacroExpandedProgram([typed], false);

		final root = Path.join([Sys.getCwd(), ".tmp", "m14_abstract_binary_cross_backend"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final cases = [
			{
				target: "js-native",
				executable: "node",
				fileName: "out.js",
				callText: "__hx_cls_Token.mergeArbitrarily"
			},
			{
				target: "python-native",
				executable: "python3",
				fileName: "out.py",
				callText: "Token.mergeArbitrarily"
			},
		];
		final expected = "15\nx!\n106\n17\nz?\n5\nvalue4\n";
		for (entry in cases) {
			final outputPath = Path.join([root, entry.fileName]);
			final context = new BackendContext(Path.join([root, entry.target]), outputPath, "Main", true, false, new StringMap<String>());
			final emitted = BackendRegistry.createForTarget(entry.target).emit(program, context);
			final generated = File.getContent(emitted.entryPath);
			assertTrue(generated.indexOf(entry.callText) >= 0, entry.target + " rebound or lost the arbitrary-name helper selected by the shared typer");
			final executed = run(entry.executable, emitted.entryPath);
			assertTrue(executed.code == 0, entry.target + " abstract-binary artifact failed: " + executed.stderr);
			assertTrue(executed.stdout == expected, entry.target + " produced unexpected shared binary output: " + executed.stdout);
		}
		deleteRecursive(root);
	}
}
