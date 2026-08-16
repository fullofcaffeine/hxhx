import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Proves that a primitive-backed abstract declared as a module's main type owns
	its public static functions in generated OCaml.

	The caller uses the normalized target names. The provider module must define
	the same names from the Haxe declaration, without a library-specific shim.
**/
class M14Stage3AbstractStaticFunctionIntegrationTest {
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

	static function commandOutput(command:String, ?arguments:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, arguments == null ? [] : arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function program(classPath:String, modules:Array<ResolvedModule>):backend.GenIrProgram {
		final index = TyperIndex.build(modules);
		final loader = new ModuleLoader([classPath], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready(modules);
		return MacroStage.expandProgram([
			for (module in modules)
				TyperStage.typeResolvedModule(module, index, loader, true)
		], []);
	}

	static function main():Void {
		final root = Path.join([Sys.getCwd(), ".tmp", "m14_stage3_abstract_static_function"]);
		final sourceRoot = Path.join([root, "src"]);
		final ticketDir = Path.join([sourceRoot, "demo"]);
		final outDir = Path.join([root, "out"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		FileSystem.createDirectory(sourceRoot);
		FileSystem.createDirectory(ticketDir);

		final ticketPath = Path.join([ticketDir, "Ticket.hx"]);
		final ticketSource = [
			"package demo;",
			"abstract Ticket(String) to String {",
			"  public inline function new(value:String) this = value;",
			"  public static function Empty():Ticket return new Ticket(null);",
			"  public static function Label():String return \"abstract-static-ok\";",
			"}",
		].join("\n");
		File.saveContent(ticketPath, ticketSource);

		final mainPath = Path.join([sourceRoot, "Main.hx"]);
		final mainSource = [
			"class Main {",
			"  static function main():Void {",
			"    demo.Ticket.Empty();",
			"    Sys.println(demo.Ticket.Label());",
			"  }",
			"}",
		].join("\n");
		File.saveContent(mainPath, mainSource);

		var thrown:Dynamic = null;
		try {
			final baseline = commandOutput("haxe", ["-cp", sourceRoot, "--run", "Main"]);
			assertTrue(baseline.code == 0, "Haxe 4.3.7 rejected the focused abstract-static program: " + baseline.stderr);
			assertTrue(baseline.stdout == "abstract-static-ok\n", "unexpected Haxe 4.3.7 abstract-static output:\n" + baseline.stdout);

			final modules = [
				new ResolvedModule("Main", mainPath, ParserStage.parse(mainSource, mainPath)),
				new ResolvedModule("demo.Ticket", ticketPath, ParserStage.parse(ticketSource, ticketPath)),
			];
			final executable = EmitterStage.emitToDir(program(sourceRoot, modules), outDir, true);
			final generatedTicket = File.getContent(Path.join([outDir, "Demo_Ticket.ml"]));
			final generatedMain = File.getContent(Path.join([outDir, "Main.ml"]));
			assertTrue(generatedTicket.indexOf("let rec empty") >= 0 || generatedTicket.indexOf("let empty") >= 0,
				"the primary abstract module did not define its normalized Empty function");
			assertTrue(generatedTicket.indexOf("let rec label") >= 0 || generatedTicket.indexOf("let label") >= 0,
				"the primary abstract module did not define its normalized Label function");
			assertTrue(generatedMain.indexOf("Demo_Ticket.empty") >= 0 && generatedMain.indexOf("Demo_Ticket.label") >= 0,
				"the generated caller and abstract provider disagree about static function ownership");

			final executed = commandOutput(executable);
			assertTrue(executed.code == 0, "focused abstract-static executable failed: " + executed.stderr);
			assertTrue(executed.stdout == "abstract-static-ok\n", "unexpected focused abstract-static output:\n" + executed.stdout);
		} catch (error:Dynamic) {
			thrown = error;
		}

		if (thrown != null) {
			Sys.println("debug_out=" + root);
			throw thrown;
		}
		deleteRecursive(root);
	}
}
