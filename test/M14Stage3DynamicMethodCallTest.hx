import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds calls of class methods through `Dynamic` receivers with the Stage3
	native emitter and compares the program with upstream Haxe.

	Why
	- `final d:Dynamic = new Late(); d.pick();` read the method from the
	  instance's field storage. Methods are not stored there, so the read gave
	  null, and the native program applied null as a function and crashed with
	  exit 138 (SIGBUS). Upstream Haxe 4.3.7 calls the method.

	What
	- `stage3_dynamic_method_call` calls overridden, inherited, interface, and
	  ordinary methods, with omitted optional arguments, default values, and
	  Int, Float, Bool, and String parameters, and calls function values stored
	  in fields. The native executable must print exactly what upstream prints.
	- A call that cannot reach a method must raise an error that `try`/`catch`
	  can handle, and that error must name the method.
	- Arguments and results keep their real values: a Bool passed to a stored
	  function, a `flag:Bool = true` parameter, an abstract over Float given an
	  Int, and the result of a Dynamic call used in a condition or comparison.
**/
class M14Stage3DynamicMethodCallTest {
	static final fixture = "test/fixtures/stage3_dynamic_method_call";

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
		M14Stage3RuntimeFixture.observe({
			command: "node_modules/.bin/haxe",
			arguments: ["-cp", fixture, "--run", "Main"],
			expected: expected
		});
		final outDir = ".tmp/m14_stage3_dynamic_method_call";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: fixture});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_DYNAMIC_METHOD_CALL_RUNTIME:PASS");
	}

	/**
		Upstream either stops on these calls or reports its own text, so they
		are compared with the recorded native output. Each named error must be
		catchable.
	**/
	static function namedErrors():Void {
		final fixtureErrors = "test/fixtures/stage3_dynamic_method_call_errors";
		final path = fixtureErrors + "/Main.hx";
		final expected = File.getContent(fixtureErrors + "/expected.stdout");
		final outDir = ".tmp/m14_stage3_dynamic_method_call_errors";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: fixtureErrors});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_DYNAMIC_METHOD_CALL_ERRORS:PASS");
	}

	static function main():Void {
		compareWithUpstream();
		namedErrors();
	}
}
