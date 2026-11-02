import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a program that passes typed methods to `Reflect.callMethod` with the
	Stage3 native emitter and compares its output with upstream Haxe 4.3.7.

	Why
	- `Reflect.callMethod` takes `haxe.Constraints.Function`, an abstract over
	  Dynamic with no `@:from` conversion. Upstream accepts any function value
	  there. Stage3's call selection rejected `Reflect.callMethod(holder,
	  holder.add, [7])` with "No compatible method signature for callMethod"
	  (haxe_ocaml-6zeuc).

	What
	- `reflect_call_method` passes an instance method (keeping its receiver),
	  a two-argument method, a static method, a local function, a value stored
	  in a `Function` local, and a value passed through a `Function` parameter.
	  The native executable must print exactly what upstream prints.
	- A non-callable value (an Int literal, a String local) passed as
	  `Function` must still be rejected, by upstream and by Stage3.
**/
class M14Stage3ReflectCallMethodTest {
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

	/** Upstream and Stage3 must both reject `source`; `upstreamText` is part of upstream's diagnostic. */
	static function rejectLikeUpstream(name:String, source:String, upstreamText:String):Void {
		final root = ".tmp/m14_stage3_reflect_call_method_" + name;
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		File.saveContent(path, source);
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--no-output"]);
		process.stdout.readAll();
		final stderr = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		if (status == 0 || stderr.indexOf(upstreamText) < 0)
			throw name + ": upstream Haxe must reject the program with <" + upstreamText + ">, got: " + stderr;
		final message = try {
			M14Stage3RuntimeFixture.prepareProgram({source: source, path: path, root: root});
			null;
		} catch (error:haxe.Exception) {
			error.message;
		}
		deleteRecursive(root);
		if (message == null || message.indexOf("No compatible method signature for callMethod") < 0)
			throw name + ": Stage3 must reject the non-callable value while typing, got: " + message;
		Sys.println("M14_STAGE3_REFLECT_CALL_METHOD_REJECT_" + name.toUpperCase() + ":PASS");
	}

	static function main():Void {
		rejectLikeUpstream("int_literal", 'class Main {\n\tstatic function main() {\n\t\tSys.println(Reflect.callMethod(null, 5, []));\n\t}\n}\n',
			"Int should be haxe.Function");
		rejectLikeUpstream("string_local",
			'class Main {\n\tstatic function main() {\n\t\tfinal text = "x";\n\t\tSys.println(Reflect.callMethod(null, text, []));\n\t}\n}\n',
			"String should be haxe.Function");
		final source = "test/fixtures/reflect_call_method";
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_reflect_call_method";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_REFLECT_CALL_METHOD:PASS");
	}
}
