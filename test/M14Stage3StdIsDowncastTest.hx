import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds class type tests and downcasts with the Stage3 native emitter and
	compares the program with upstream Haxe.

	Why
	- Stage3 used to emit every `Std.is(value, type)` whose type argument was
	  not a plain class name as the constant `true`, and every such
	  `Std.downcast(value, type)` as the constant null, without evaluating the
	  arguments. With a class name, both calls stopped at emit time with an
	  unrelated "first-class type values" error, so neither form worked.

	What
	- `stage3_std_is_downcast` runs `Std.is`, `Std.isOfType`, `(value is T)`,
	  `Std.downcast`, and `Std.instance` on classes, subclasses, a
	  two-level subclass, interfaces, an interface that extends another,
	  `Dynamic` and `Any` operands, `null`, primitives, an anonymous object, and
	  an array. The native executable must print exactly what upstream Haxe
	  4.3.7 prints. Each logged operand must also run exactly once.
	- A type argument that Stage3 cannot test must stop the build with a
	  named error: a `Dynamic` value holding a class, the core types Int,
	  Float, Bool, String and Dynamic, and an enum.
**/
class M14Stage3StdIsDowncastTest {
	static final fixture = "test/fixtures/stage3_std_is_downcast";

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function compareWithUpstream():Void {
		final path = fixture + "/Main.hx";
		final expected = File.getContent(fixture + "/expected.stdout");
		// `Std.is` and `Std.instance` are deprecated; the warning would fill stderr.
		M14Stage3RuntimeFixture.observe({
			command: "node_modules/.bin/haxe",
			arguments: ["-w", "-WDeprecated", "-cp", fixture, "--run", "Main"],
			expected: expected
		});
		final outDir = ".tmp/m14_stage3_std_is_downcast";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: fixture});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_STD_IS_DOWNCAST_RUNTIME:PASS");
	}

	static function emitError(name:String, body:String):String {
		final root = ".tmp/m14_stage3_std_is_downcast_" + name;
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final source = "enum Choice {\n\tFirst;\n}\n" + "class Base {\n\tpublic function new() {}\n}\n" + "class Main {\n" + body + "\n}\n";
		File.saveContent(path, source);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: source, path: path, root: root});
		final result = try {
			EmitterStage.emitToDir(new MacroExpandedProgram(program, false), root + "/out");
			"emitted";
		} catch (error:haxe.Exception) {
			error.message;
		}
		deleteRecursive(root);
		return result;
	}

	/** A type argument without a supported runtime test is an emit-time error, never a constant. */
	static function rejectUnsupportedTypeArguments():Void {
		final cases = [
			{
				name: "dynamic_is",
				expected: "requires a direct checked nominal type argument",
				body: "\tstatic function check(v:Dynamic, t:Dynamic):Bool\n\t\treturn Std.is(v, t);\n" +
				"\tstatic function main()\n\t\tSys.println(check(new Base(), null));"
			},
			{
				name: "dynamic_downcast",
				expected: "requires a direct checked nominal type argument",
				body: "\tstatic function narrow(v:Base, c:Dynamic):Base\n\t\treturn Std.downcast(v, c);\n" +
				"\tstatic function main()\n\t\tSys.println(narrow(new Base(), null) == null);"
			},
			{
				name: "int",
				expected: "does not support runtime type operands for runtime-core:Int",
				body: "\tstatic function main() {\n\t\tfinal v:Dynamic = 1;\n\t\tSys.println(Std.is(v, Int));\n\t}"
			},
			{
				name: "float",
				expected: "does not support runtime type operands for runtime-core:Float",
				body: "\tstatic function main() {\n\t\tfinal v:Dynamic = 1.5;\n\t\tSys.println(Std.isOfType(v, Float));\n\t}"
			},
			{
				name: "bool",
				expected: "does not support runtime type operands for runtime-core:Bool",
				body: "\tstatic function main() {\n\t\tfinal v:Dynamic = true;\n\t\tSys.println(v is Bool);\n\t}"
			},
			{
				name: "string",
				expected: "does not support runtime type operands for runtime-core:String",
				body: "\tstatic function main() {\n\t\tfinal v:Dynamic = \"text\";\n\t\tSys.println(Std.is(v, String));\n\t}"
			},
			{
				name: "dynamic_type",
				expected: "does not support runtime type operands for runtime-core:Dynamic",
				body: "\tstatic function main() {\n\t\tfinal v:Dynamic = 1;\n\t\tSys.println(Std.isOfType(v, Dynamic));\n\t}"
			},
			{
				name: "enum",
				expected: "does not support runtime type operands for runtime-enum",
				body: "\tstatic function main() {\n\t\tfinal v:Dynamic = First;\n\t\tSys.println(Std.is(v, Choice));\n\t}"
			}
		];
		for (entry in cases) {
			final result = emitError(entry.name, entry.body);
			if (result.indexOf(entry.expected) < 0)
				throw entry.name + ": expected an emit-time error containing <" + entry.expected + ">, got <" + result + ">";
		}
		Sys.println("M14_STAGE3_STD_IS_DOWNCAST_REJECTIONS:PASS");
	}

	static function main():Void {
		// The rejected builds run first, so the passing build also proves a
		// failed emit leaves no emitter state behind.
		rejectUnsupportedTypeArguments();
		compareWithUpstream();
	}
}
