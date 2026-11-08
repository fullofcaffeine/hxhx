import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds `Reflect` and `Type` programs with the Stage3 native emitter and
	compares them with upstream Haxe.

	Why
	- Stage3 used to replace calls spelled `Reflect.hasField`, `Reflect.field`,
	  `Reflect.fields`, `Reflect.getProperty`, `Reflect.setProperty`,
	  `Reflect.isFunction`, `Type.getInstanceFields`, and `Type.typeof` with
	  fixed values. `hasField` was always false, `isFunction` always true, and
	  the others returned an invalid value, so a native program printed
	  `hasField false false` where upstream prints `hasField true false`.
	  Because the match used the spelling, a project class named `Reflect` was
	  replaced the same way.

	What
	- `stage3_reflect_type` runs the standard `Reflect` and `Type` calls on
	  anonymous objects, class instances, a subclass instance, primitives,
	  functions, arrays, strings, and enum values. The native executable must
	  print exactly what upstream Haxe 4.3.7 prints.
	- `stage3_reflect_type_user_class` calls a project class `tools.Reflect`
	  through the short name `Reflect`; its own methods must run.
	  The fixture also reads methods and accessor properties by name, calls
	  `Reflect.field` and `Reflect.setField` as function values, and uses a
	  static import and `using Type`.
	- `Reflect.callMethod` with a null argument array calls the function with
	  no arguments. Upstream `--interp` raises Null Access there, so this is a
	  native-only check of the documented Stage3 choice.
	- `Type` methods that need class data Stage3 does not register stop the
	  build with a named error.
**/
class M14Stage3ReflectTypeTest {
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

	static function compareWithUpstream(label:String, source:String):Void {
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_reflect_type_" + label;
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_REFLECT_TYPE_" + label.toUpperCase() + ":PASS");
	}

	/** Emit an inline program; return the executable path, or the emit-time error. */
	static function emitInline(label:String, source:String):{executable:Null<String>, error:Null<String>, root:String} {
		final root = ".tmp/m14_stage3_reflect_type_inline_" + label;
		deleteRecursive(root);
		FileSystem.createDirectory(root + "/src");
		final path = root + "/src/Main.hx";
		File.saveContent(path, source);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: source, path: path, root: root + "/src"});
		try {
			return {executable: EmitterStage.emitToDir(new MacroExpandedProgram(program, false), root + "/out"), error: null, root: root};
		} catch (error:String) {
			// A request that stops early leaves per-request emitter state behind;
			// the compiler request pipeline clears it the same way.
			EmitterStage.resetRequestState();
			return {executable: null, error: error, root: root};
		}
	}

	/** A null argument array is an empty argument list on the native target. */
	static function callMethodNullArguments():Void {
		final emitted = emitInline("call_method_null",
			"class Point {\n"
			+ "\tpublic var x:Int = 4;\n"
			+ "\tpublic function new() {}\n"
			+ "\tpublic function twice():Int\n\t\treturn x * 2;\n"
			+ "}\n"
			+ "class Main {\n"
			+ "\tstatic function main():Void {\n"
			+ "\t\tfinal point = new Point();\n"
			+ "\t\tSys.println(Reflect.callMethod(point, Reflect.field(point, \"twice\"), null));\n"
			+ "\t}\n"
			+ "}\n");
		if (emitted.executable == null)
			throw "callMethod program failed to emit: " + emitted.error;
		M14Stage3RuntimeFixture.observe({command: emitted.executable, arguments: [], expected: "8\n"});
		deleteRecursive(emitted.root);
		Sys.println("M14_STAGE3_REFLECT_TYPE_CALL_METHOD_NULL:PASS");
	}

	static function rejectUnregistered(method:String, call:String, expected:String):Void {
		final emitted = emitInline("reject_"
			+ method,
			"class Point {\n"
			+ "\tpublic function new() {}\n"
			+ "}\n"
			+ "class Main {\n"
			+ "\tstatic function main():Void {\n"
			+ "\t\tfinal c = Type.getClass(new Point());\n"
			+ "\t\tSys.println("
			+ call
			+ ");\n"
			+ "\t}\n"
			+ "}\n");
		deleteRecursive(emitted.root);
		if (emitted.error == null || emitted.error.indexOf(expected) < 0)
			throw "expected emit-time rejection containing <" + expected + ">, got <" + emitted.error + ">";
		Sys.println("M14_STAGE3_REFLECT_TYPE_REJECT_" + method.toUpperCase() + ":PASS");
	}

	static function main():Void {
		compareWithUpstream("runtime", "test/fixtures/stage3_reflect_type");
		compareWithUpstream("user_class", "test/fixtures/stage3_reflect_type_user_class");
		callMethodNullArguments();
		rejectUnregistered("getClassFields", "Type.getClassFields(c)",
			"Type.getClassFields is not supported natively yet; Stage3 does not register static field lists");
		rejectUnregistered("createEmptyInstance", "Type.createEmptyInstance(c)",
			"Type.createEmptyInstance is not supported natively yet; Stage3 does not register class constructors");
	}
}
