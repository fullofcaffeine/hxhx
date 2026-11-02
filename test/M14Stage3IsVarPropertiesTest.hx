import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds `@:isVar` property programs with the Stage3 native emitter and compares them with upstream Haxe.

	Why
	- Inside a property's own accessor, `field = value` writes the physical
	  field instead of calling the setter. Typing marks such a write as
	  property storage access. Stage3 admitted it as a statement, but rejected
	  it in value position, such as `return level = value`. That was the usual
	  way to write a setter. The write then became the `(Obj.magic 0)`
	  placeholder, so the field kept its initializer value and the setter
	  returned garbage.

	What
	- `stage3_isvar_properties` covers `(get, set)`, `(default, set)`, and
	  `(null, set)` properties, `return field = value`, writes from inside and
	  outside the class, `++`, and compound assignment through the property.
	  The native executable must print exactly what upstream Haxe 4.3.7 prints.
	- `stage3_isvar_properties_static` is known failing until PR #131 adds
	  native static field storage (Bead haxe_ocaml-nq65n). The test requires
	  that it still differs, so the fix is noticed and its lines are folded in.
**/
class M14Stage3IsVarPropertiesTest {
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

	/** Check upstream, then build the native executable; returns it with the expected output. */
	static function build(source:String, label:String):{executable:String, expected:String, outDir:String} {
		final path = source + "/Main.hx";
		final expected = File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_isvar_properties_" + label;
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		return {executable: EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir), expected: expected, outDir: outDir};
	}

	static function main():Void {
		final instance = build("test/fixtures/stage3_isvar_properties", "instance");
		M14Stage3RuntimeFixture.observe({command: instance.executable, arguments: [], expected: instance.expected});
		deleteRecursive(instance.outDir);
		Sys.println("M14_STAGE3_ISVAR_PROPERTIES:PASS");
		final known = build("test/fixtures/stage3_isvar_properties_static", "static");
		var nowPasses = false;
		try {
			M14Stage3RuntimeFixture.observe({command: known.executable, arguments: [], expected: known.expected});
			nowPasses = true;
		} catch (_:Dynamic) {}
		deleteRecursive(known.outDir);
		if (nowPasses)
			throw "stage3_isvar_properties_static now matches upstream: move its lines into stage3_isvar_properties and remove the known-failing check";
		Sys.println("M14_STAGE3_ISVAR_PROPERTIES_STATIC:KNOWN_FAILING (PR #131, haxe_ocaml-nq65n)");
	}
}
