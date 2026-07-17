import backend.BackendContext;
import backend.BackendRegistry;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Builds and executes the repo-owned `Int64 / Int` contract through C++. **/
class M14CppInt64DivIntIntegrationTest {
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
		final sourcePath = "test/oracle/cpp_int64_div_int_seed/src/Main.hx";
		final source = HxConditionalCompilation.filterSource(File.getContent(sourcePath), new StringMap<String>());
		final int64Source = [
			"package haxe;",
			"@:transitive abstract Int64(Int) from Int to Int {",
			"  public static function ofInt(value:Int):Int64 return cast value;",
			"  public static function make(high:Int, low:Int):Int64 return cast low;",
			"  public static function toStr(value:Int64):String return '';",
			"  public static function add(left:Int64, right:Int64):Int64 return left;",
			"  public static function div(left:Int64, right:Int64):Int64 return left;",
			"  @:op(A / B) private static inline function divInt(value:Int64, divisor:Int):Int64 return value;",
			"}",
		].join("\n");
		final int64Resolved = new ResolvedModule("haxe.Int64", "haxe/Int64.hx", ParserStage.parse(int64Source, "haxe/Int64.hx"));
		final mainResolved = new ResolvedModule("Main", sourcePath, ParserStage.parse(source, sourcePath));
		final resolved = [int64Resolved, mainResolved];
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader(["."], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready(resolved);
		final provisional = TyperStage.typeResolvedModule(mainResolved, index, loader, true);
		final typed = TypedAbstractOperatorLowering.lowerModules([provisional], index)[0];
		final program = new MacroExpandedProgram([typed], false);

		final root = Path.join([Sys.getCwd(), ".tmp", "m14_cpp_int64_div_int"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final context = new BackendContext(root, null, "Main", true, true, new StringMap<String>());
		final result = BackendRegistry.createForTarget("cpp-native").emit(program, context);
		assertTrue(result.builtExecutable, "focused Int64 / Int C++ artifact did not build");

		final generated = File.getContent(Path.join([root, "src", "Main.cpp"]));
		assertTrue(generated.indexOf("Int64::divInt") < 0, "C++ emitted a nonexistent Int64.divInt helper");
		assertTrue(generated.indexOf("Int64::div(") < 0, "C++ emitted Int64.div instead of the native carrier helper");
		assertTrue(generated.split("__hxhx_int64_div(").length > 5, "C++ did not route Int64 division through the checked carrier helper");
		final rawCarrierDiv = new EReg("__hxhx_abstract_binary_left_[0-9]+ / __hxhx_abstract_binary_right_[0-9]+", "");
		assertTrue(!rawCarrierDiv.match(generated), "C++ retained raw signed division for a typed Int64 operator");
		assertTrue(generated.indexOf("if (divisor == 0) throw std::runtime_error(\"divide by zero\")") >= 0,
			"C++ Int64 division does not preserve Haxe's divide-by-zero exception");
		assertTrue(generated.indexOf("dividend == std::numeric_limits<long long>::min() && divisor == -1") >= 0,
			"C++ Int64 division does not guard the minimum-value divided by negative-one boundary");

		final executed = commandOutput(result.entryPath);
		assertTrue(executed.code == 0, "focused Int64 / Int executable failed: " + executed.stderr);
		final expected = File.getContent("test/oracle/cpp_int64_div_int_seed/expected.stdout");
		assertTrue(executed.stdout == expected, "unexpected focused Int64 / Int stdout:\n" + executed.stdout);
		deleteRecursive(root);
	}
}
