import backend.BackendContext;
import backend.BackendRegistry;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Builds and executes the repo-owned static `Int64` equality contract through C++. **/
class M14CppInt64EqualityIntegrationTest {
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

	static function commandOutput(command:String):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function main():Void {
		final sourcePath = "test/oracle/cpp_int64_equality_seed/src/Main.hx";
		final source = HxConditionalCompilation.filterSource(File.getContent(sourcePath), new StringMap<String>());
		final parsed = ParserStage.parse(source, sourcePath);
		final typed = TyperStage.typeModule(parsed);
		final program = new MacroExpandedProgram([typed], false);

		final root = Path.join([Sys.getCwd(), ".tmp", "m14_cpp_int64_equality"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final context = new BackendContext(root, null, "Main", true, true, new StringMap<String>());
		final result = BackendRegistry.createForTarget("cpp-native").emit(program, context);
		assertTrue(result.builtExecutable, "focused Int64 equality C++ artifact did not build");

		final generated = File.getContent(Path.join([root, "src", "Main.cpp"]));
		assertTrue(generated.indexOf("Int64::eq") < 0, "C++ emitted a nonexistent Int64::eq helper instead of carrier equality");
		assertTrue(generated.indexOf("Int64::neq") < 0, "C++ emitted a nonexistent Int64::neq helper instead of carrier inequality");
		assertTrue(generated.indexOf(" == ") >= 0, "C++ did not emit native carrier equality");
		assertTrue(generated.indexOf(" != ") >= 0, "C++ did not emit native carrier inequality");

		final executed = commandOutput(result.entryPath);
		assertTrue(executed.code == 0, "focused Int64 equality executable failed: " + executed.stderr);
		final expected = File.getContent("test/oracle/cpp_int64_equality_seed/expected.stdout");
		assertTrue(executed.stdout == expected, "unexpected focused Int64 equality stdout:\n" + executed.stdout);
		deleteRecursive(root);
	}
}
