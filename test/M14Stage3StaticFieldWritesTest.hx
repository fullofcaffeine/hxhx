import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Prove that native OCaml programs store writes to static fields, as Haxe 4.3.7 does.

	Why
	- The native Stage3 emitter used to bind every static field to an immutable OCaml
	  `let`. A write such as `count = 5`, `count++`, `Main.items = []`, or
	  `Registry.total += 0.25` then emitted `()` or a placeholder number, so the
	  program kept printing the initial value without any error.

	What
	- `stage3_static_field_writes` writes Int, Float, String, Bool, Array, class, and
	  nullable statics with plain assignment, compound assignment, and prefix and
	  postfix increments, in statement and value position. It writes through the
	  bare name and the qualified name inside the owning class, and from another
	  module. It also covers a counter that closures update, a `(default, null)`
	  property, uninitialized statics, startup order inside one module and across
	  modules, and reads of written statics from both modules.
	- The upstream run fixes `expected.stdout`; the native executable must print the
	  same lines.
	- A static write that the emitter cannot store yet must stop emission with a
	  named error instead of producing `()` or a placeholder.
**/
class M14Stage3StaticFieldWritesTest {
	static final fixture = "test/fixtures/stage3_static_field_writes";

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
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", fixture, "--run", "Main"], expected: expected});
		Sys.println("M14_STAGE3_STATIC_FIELD_WRITES_UPSTREAM:PASS");
		final outDir = ".tmp/m14_stage3_static_field_writes";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: fixture});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_STATIC_FIELD_WRITES_NATIVE:PASS");
		deleteRecursive(outDir);
	}

	/**
		Static writes without a native representation must stop emission with a named
		error. Upstream Haxe accepts both programs: `|=` sets bits of an Int static,
		and `+=` on a Dynamic static adds at run time.
	**/
	static function rejectUnsupportedWrites():Void {
		final cases = [
			{
				name: "bitwise",
				expected: "unsupported OCaml static field update: |= on Int (Main.flags)",
				source: "class Main {\n\tstatic var flags = 1;\n\tstatic function main() {\n\t\tflags |= 2;\n\t\tSys.println(flags);\n\t}\n}\n"
			},
			{
				name: "dynamic",
				expected: "unsupported OCaml static field update: += on Dynamic (Main.value)",
				source: "class Main {\n\tstatic var value:Dynamic = 1;\n\tstatic function main() {\n\t\tvalue += 2;\n\t\tSys.println(value);\n\t}\n}\n"
			}
		];
		for (shape in cases) {
			final root = ".tmp/m14_stage3_static_field_writes_" + shape.name;
			deleteRecursive(root);
			FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			File.saveContent(path, shape.source);
			final program = M14Stage3RuntimeFixture.prepareProgram({source: shape.source, path: path, root: root});
			final result = try {
				EmitterStage.emitToDir(new MacroExpandedProgram(program, false), root + "/out");
			} catch (error:haxe.Exception) {
				"error: " + error.message;
			}
			deleteRecursive(root);
			if (!StringTools.startsWith(result, "error: ") || result.indexOf(shape.expected) < 0)
				throw "an unsupported " + shape.name + " static write must fail at emit time, got: " + result;
		}
		Sys.println("M14_STAGE3_STATIC_FIELD_WRITES_UNSUPPORTED:PASS");
	}

	/**
		An uninitialized Int, Float, or Bool static starts at 0, 0.0, or false natively,
		as on Haxe's static targets (C++, Java, C#). `haxe --interp` starts them at
		null instead, so this check has a native-only expectation.
	**/
	static function requireBasicDefaults():Void {
		final root = ".tmp/m14_stage3_static_field_writes_defaults";
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final source = "class Main {\n\tstatic var i:Int;\n\tstatic var f:Float;\n\tstatic var b:Bool;\n"
			+ "\tstatic function main() {\n\t\tSys.println(i == 0);\n\t\tSys.println(f == 0);\n\t\tSys.println(b == false);\n"
			+ "\t\ti++;\n\t\tf += 0.5;\n\t\tb = !b;\n\t\tSys.println(i + \" \" + f + \" \" + b);\n\t}\n}\n";
		File.saveContent(path, source);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: source, path: path, root: root});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), root + "/out");
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: "true\ntrue\ntrue\n1 0.5 true\n"});
		deleteRecursive(root);
		Sys.println("M14_STAGE3_STATIC_FIELD_WRITES_DEFAULTS:PASS");
	}

	static function main():Void {
		// The rejected emits run first: a failed emit must leave no emitter state behind.
		rejectUnsupportedWrites();
		compareWithUpstream();
		requireBasicDefaults();
	}
}
