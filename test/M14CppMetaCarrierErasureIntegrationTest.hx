import backend.BackendContext;
import backend.BackendRegistry;
import backend.GenIrProgram;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Builds the focused Class<T>/Enum<T> runtime-metadata contract through C++. **/
class M14CppMetaCarrierErasureIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function countOccurrences(haystack:String, needle:String):Int {
		var count = 0;
		var offset = 0;
		while (true) {
			final found = haystack.indexOf(needle, offset);
			if (found < 0)
				return count;
			count++;
			offset = found + needle.length;
		}
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

	static function typedSource(filePath:String, source:String):TypedModule {
		return TyperStage.typeModule(ParserStage.parse(source, filePath));
	}

	static function program():GenIrProgram {
		final mainSource = HxConditionalCompilation.filterSource(File.getContent("test/oracle/cpp_meta_carrier_erasure_seed/src/Main.hx"),
			new StringMap<String>());
		final classSource = "class Class<T> { public var __type:T; }";
		final enumSource = "class Enum<T> { public var __type:T; }";
		final typeSource = [
			"class Type {",
			"  public static function getClass<T>(value:T):Class<T> return null;",
			"  public static function getEnum(value:Dynamic):Enum<Dynamic> return null;",
			"  public static function getClassName(value:Class<Dynamic>):String return '';",
			"  public static function getEnumName(value:Enum<Dynamic>):String return '';",
			"  public static function resolveClass(name:String):Class<Dynamic> return null;",
			"  public static function resolveEnum(name:String):Enum<Dynamic> return null;",
			"  public static function typeof(value:Dynamic):ValueType return null;",
			"  public static function enumEq<T>(left:T, right:T):Bool return false;",
			"}",
			"enum ValueType {",
			"  TNull;",
			"  TInt;",
			"  TFloat;",
			"  TBool;",
			"  TObject;",
			"  TFunction;",
			"  TClass(c:Class<Dynamic>);",
			"  TEnum(e:Enum<Dynamic>);",
			"  TUnknown;",
			"}",
		].join("\n");
		return MacroStage.expandProgram([
			typedSource("Main.hx", mainSource),
			typedSource("Class.hx", classSource),
			typedSource("Enum.hx", enumSource),
			typedSource("Type.hx", typeSource)
		], []);
	}

	static function main():Void {
		final root = Path.join([Sys.getCwd(), ".tmp", "m14_cpp_meta_carrier_erasure"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final context = new BackendContext(root, null, "Main", true, true, new StringMap<String>());
		final result = BackendRegistry.createForTarget("cpp-native").emit(program(), context);
		assertTrue(result.builtExecutable, "focused C++ meta-carrier artifact did not build");

		final generated = File.getContent(Path.join([root, "src", "Main.cpp"]));
		assertTrue(countOccurrences(generated, "struct Class {") == 1, "C++ should emit one non-template Class metadata carrier");
		assertTrue(countOccurrences(generated, "struct Enum {") == 1, "C++ should emit one non-template Enum metadata carrier");
		assertTrue(generated.indexOf("template<typename T>\nstruct Class;") < 0, "C++ should not forward-declare Class as a template");
		assertTrue(generated.indexOf("template<typename T>\nstruct Enum;") < 0, "C++ should not forward-declare Enum as a template");
		assertTrue(generated.indexOf("Class<") < 0, "C++ should erase every Class<T> runtime carrier use");
		assertTrue(generated.indexOf("Enum<") < 0, "C++ should erase every Enum<T> runtime carrier use");
		assertTrue(generated.indexOf("TDynamic") < 0, "C++ should not invent a Dynamic template placeholder for erased metadata");
		assertTrue(generated.indexOf("T__fn") < 0, "C++ should not leak a function type parameter into an erased metadata carrier");
		assertTrue(generated.indexOf("__hxhx_make_shared_Class") < 0, "C++ should not emit a generic factory for the Class metadata carrier");
		assertTrue(generated.indexOf("__hxhx_make_shared_Enum") < 0, "C++ should not emit a generic factory for the Enum metadata carrier");
		assertTrue(generated.indexOf("TClass(std::shared_ptr<Class> c)") >= 0, "ValueType.TClass should accept the erased Class carrier");
		assertTrue(generated.indexOf("TEnum(std::shared_ptr<Enum> e)") >= 0, "ValueType.TEnum should accept the erased Enum carrier");
		assertTrue(generated.indexOf("template<typename T>\nstruct GenericBox;") >= 0, "ordinary generic classes should remain C++ templates");
		assertTrue(generated.indexOf("GenericBox<int>") >= 0, "ordinary generic class uses should preserve their concrete type arguments");

		final executed = commandOutput(result.entryPath);
		assertTrue(executed.code == 0, "focused C++ meta-carrier executable failed: " + executed.stderr);
		final expected = File.getContent("test/oracle/cpp_meta_carrier_erasure_seed/expected.stdout");
		assertTrue(executed.stdout == expected, "unexpected focused C++ meta-carrier stdout:\n" + executed.stdout);
		deleteRecursive(root);
	}
}
