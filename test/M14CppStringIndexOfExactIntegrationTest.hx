import HxExpr;
import backend.BackendContext;
import backend.BackendRegistry;
import backend.GenIrProgram;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Builds the focused ordinary and exact typed String.indexOf contract through C++. **/
class M14CppStringIndexOfExactIntegrationTest {
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

	static function program():GenIrProgram {
		final source = HxConditionalCompilation.filterSource(File.getContent("test/oracle/cpp_string_index_of_exact_seed/src/Main.hx"),
			new StringMap<String>());
		final typed = TyperStage.typeModule(ParserStage.parse(source, "Main.hx"));
		return MacroStage.expandProgram([typed], []);
	}

	static function exactCall(methodArgs:Array<HxExpr>):String {
		final owner = new HxClassDecl("ExactStringCallOwner", false, [], []);
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		names.set("ExactStringCallOwner", true);
		classes.set("ExactStringCallOwner", owner);
		final scope = @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: classes, all: [owner]}, "int");
		final expression = TypedExactCallSource.encodeInstance("String", "String.indexOf", "indexOf", "Int",
			EBinop("+", EString("native"), EString("-target")), methodArgs);
		final inferredType = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(expression, scope);
		assertTrue(inferredType == "int", "exact typed String.indexOf should retain its Int result, got " + inferredType);
		return @:privateAccess backend.cpp.CppTargetCore.renderExpr(expression, scope);
	}

	static function main():Void {
		final exactDefault = exactCall([EString("target")]);
		assertTrue(exactDefault == '__hxhx_index_of((std::string("native") + std::string("-target")), std::string("target"), 0)',
			"exact typed String.indexOf did not use the native helper: " + exactDefault);
		final exactOffset = exactCall([EString("target"), EInt(2)]);
		assertTrue(exactOffset.indexOf("__hxhx_index_of(") == 0 && exactOffset.indexOf(", 2)") > 0,
			"exact typed String.indexOf lost its explicit start position: " + exactOffset);
		assertTrue(exactDefault.indexOf(".indexOf(") < 0 && exactOffset.indexOf(".indexOf(") < 0,
			"exact typed String.indexOf fell through to a C++ member call");

		final root = Path.join([Sys.getCwd(), ".tmp", "m14_cpp_string_index_of_exact"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final context = new BackendContext(root, null, "Main", true, true, new StringMap<String>());
		final result = BackendRegistry.createForTarget("cpp-native").emit(program(), context);
		assertTrue(result.builtExecutable, "focused C++ String.indexOf artifact did not build");

		final generated = File.getContent(Path.join([root, "src", "Main.cpp"]));
		assertTrue(generated.indexOf('__hxhx_index_of((std::string("native") + std::string("-target")), std::string("target"), 0)') >= 0,
			"computed String receiver did not use the target-owned indexOf helper");
		assertTrue(generated.indexOf(".indexOf(") < 0, "generated C++ contains a nonexistent String.indexOf member call");

		final executed = commandOutput(result.entryPath);
		assertTrue(executed.code == 0, "focused C++ String.indexOf executable failed: " + executed.stderr);
		final expected = File.getContent("test/oracle/cpp_string_index_of_exact_seed/expected.stdout");
		assertTrue(executed.stdout == expected, "unexpected focused C++ String.indexOf stdout:\n" + executed.stdout);
		deleteRecursive(root);
	}
}
