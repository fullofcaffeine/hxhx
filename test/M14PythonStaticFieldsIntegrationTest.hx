import backend.BackendContext;
import backend.BackendRegistry;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.io.File;

/** Compile typed field ownership to Python and observe mutation without relying on generated spelling. */
class M14PythonStaticFieldsIntegrationTest {
	static function main():Void {
		final fixture = Path.join([Sys.getCwd(), "test", "python_static_fields"]);
		final sourcePath = Path.join([fixture, "Main.hx"]);
		final resolved = new ResolvedModule("Main", sourcePath, ParserStage.parse(File.getContent(sourcePath), sourcePath));
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader([fixture], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index, loader);
		final program = new MacroExpandedProgram([typed], false);
		final root = Path.join([Sys.getCwd(), ".tmp", "m14_python_static_fields"]);
		final context = new BackendContext(root, Path.join([root, "Main.py"]), "Main", true, false, new StringMap<String>());
		final emitted = BackendRegistry.createForTarget("python-native").emit(program, context);
		final process = new sys.io.Process("python3", [emitted.entryPath]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "Python static field fixture failed: " + stderr;
		if (stdout != File.getContent(Path.join([fixture, "expected.stdout"])))
			throw "Python changed field/local ownership or update count: " + stdout;
		Sys.println("PYTHON_STATIC_FIELDS:PASS");
	}
}
