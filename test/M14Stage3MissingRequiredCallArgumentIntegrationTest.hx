import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Proves that Stage3 does not turn a missing required call argument into null.

	Upstream Haxe rejects the source before target generation. The bootstrap
	frontend currently reaches OCaml emission, so the emitter must stop with one
	stable diagnostic and must not write the caller module.
**/
class M14Stage3MissingRequiredCallArgumentIntegrationTest {
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

	static function commandOutput(command:String, arguments:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function main():Void {
		final root = Path.join([Sys.getCwd(), ".tmp", "m14_stage3_missing_required_call_argument"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);

		try {
			final fixtures = [
				{
					label: "static",
					source: [
						"class Main {",
						"  static function required(first:Int, second:Int):Int return first + second;",
						"  static function main():Void { Sys.println(required(1)); }",
						"}",
					].join("\n")
				},
				{
					label: "pre_applied_receiver",
					source: [
						"class Main {",
						"  public function new() {}",
						"  function required(first:Int, second:Int):Int return first + second;",
						"  function invoke():Void { Sys.println(required(1)); }",
						"  static function main():Void { new Main().invoke(); }",
						"}",
					].join("\n")
				},
				{
					label: "source_receiver",
					source: [
						"class Main {",
						"  public function new() {}",
						"  function required(first:Int, second:Int):Int return first + second;",
						"  static function main():Void { Sys.println(new Main().required(1)); }",
						"}",
					].join("\n")
				}
			];
			for (fixture in fixtures) {
				final fixtureRoot = Path.join([root, fixture.label]);
				final sourceDir = Path.join([fixtureRoot, "src"]);
				final sourcePath = Path.join([sourceDir, "Main.hx"]);
				final outDir = Path.join([fixtureRoot, "out"]);
				FileSystem.createDirectory(fixtureRoot);
				FileSystem.createDirectory(sourceDir);
				File.saveContent(sourcePath, fixture.source);

				final baseline = commandOutput("haxe", ["-cp", sourceDir, "--no-output", "-main", "Main"]);
				assertTrue(baseline.code != 0, "Haxe 4.3.7 accepted the " + fixture.label + " call with a missing required argument");

				final parsed = ParserStage.parse(fixture.source, sourcePath);
				final typed = TyperStage.typeModule(parsed);
				final expanded = MacroStage.expandProgram([typed], []);
				var thrown:Dynamic = null;
				try {
					EmitterStage.emitToDir(expanded, outDir, true, false);
				} catch (error:String) {
					thrown = error;
				}

				assertTrue(thrown == "stage3 emitter: call `required` is missing required argument #2 (`second`)",
					fixture.label + " call did not report the stable missing-required-argument diagnostic: " + Std.string(thrown));
				assertTrue(!FileSystem.exists(Path.join([outDir, "Main.ml"])),
					"Stage3 wrote the " + fixture.label + " caller module after detecting a missing required argument");
			}

			final inheritedRoot = Path.join([root, "inherited_receiver"]);
			final inheritedSourceDir = Path.join([inheritedRoot, "src"]);
			final inheritedOutDir = Path.join([inheritedRoot, "out"]);
			final basePath = Path.join([inheritedSourceDir, "RequiredBase.hx"]);
			final mainPath = Path.join([inheritedSourceDir, "Main.hx"]);
			final baseSource = [
				"class RequiredBase {",
				"  public function new() {}",
				"  public function required(first:Int, second:Int):Int return first + second;",
				"}",
			].join("\n");
			final mainSource = [
				"class Main extends RequiredBase {",
				"  public function new() { super(); }",
				"  function invoke():Void { Sys.println(required(1)); }",
				"  static function main():Void { new Main().invoke(); }",
				"}",
			].join("\n");
			FileSystem.createDirectory(inheritedRoot);
			FileSystem.createDirectory(inheritedSourceDir);
			File.saveContent(basePath, baseSource);
			File.saveContent(mainPath, mainSource);
			final baseline = commandOutput("haxe", ["-cp", inheritedSourceDir, "--no-output", "-main", "Main"]);
			assertTrue(baseline.code != 0, "Haxe 4.3.7 accepted the inherited call with a missing required argument");

			final baseResolved = new ResolvedModule("RequiredBase", basePath, ParserStage.parse(baseSource, basePath));
			final mainResolved = new ResolvedModule("Main", mainPath, ParserStage.parse(mainSource, mainPath));
			final resolved = [baseResolved, mainResolved];
			final index = TyperIndex.build(resolved);
			final loader = new ModuleLoader([inheritedSourceDir], new haxe.ds.StringMap<String>(), index, _ -> false);
			loader.markResolvedAlready(resolved);
			final typed = [
				TyperStage.typeResolvedModule(baseResolved, index, loader),
				TyperStage.typeResolvedModule(mainResolved, index, loader),
			];
			var inheritedThrown:Dynamic = null;
			try {
				EmitterStage.emitToDir(MacroStage.expandProgram(typed, []), inheritedOutDir, true, false);
			} catch (error:String) {
				inheritedThrown = error;
			}
			assertTrue(inheritedThrown == "stage3 emitter: call `required` is missing required argument #2 (`second`)",
				"inherited call did not report the stable missing-required-argument diagnostic: " + Std.string(inheritedThrown));
			assertTrue(!FileSystem.exists(Path.join([inheritedOutDir, "Main.ml"])),
				"Stage3 wrote the inherited caller module after detecting a missing required argument");
		} catch (error:Dynamic) {
			deleteRecursive(root);
			throw error;
		}

		deleteRecursive(root);
	}
}
