import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Compares keyword-like names with upstream Haxe through both OCaml generators. */
class M14OcamlKeywordNamesIntegrationTest {
	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw command + " exited " + code + ": " + errors;
		return output;
	}

	static function removeTree(path:String):Void {
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				removeTree(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function main():Void {
		final fixture = "test/ocaml_keyword_names";
		final expected = File.getContent(fixture + "/expected.stdout");
		if (run("haxe", ["-cp", fixture, "--run", "Main"]) != expected)
			throw "upstream OCaml keyword names contract differs from its authored expectation";
		final path = fixture + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final root = Path.normalize(Sys.getCwd() + "/.tmp/ocaml_keyword_names_" + Std.string(Date.now().getTime()));
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), root, true);
		final actual = run(executable, []);
		File.saveContent(root + "/actual.stdout", actual);
		if (actual != expected)
			throw "native OCaml keyword names output mismatch; artifacts: " + root;
		final standalone = root + "/standalone";
		// Nested compiler processes must expand this checkout's Lix library pins.
		// The upstream executable can otherwise read a global dev registration
		// that points at a different worktree and an incompatible Reflaxe version.
		run(Path.normalize("node_modules/.bin/haxe"), [
			"-cp",
			fixture,
			"-main",
			"Main",
			"-lib",
			"reflaxe.ocaml",
			"-D",
			"ocaml_output=" + standalone,
			"-D",
			"ocaml_build=native",
			"--no-output"
		]);
		final standaloneActual = run(standalone + "/_build/default/standalone.exe", []);
		File.saveContent(root + "/standalone.stdout", standaloneActual);
		if (standaloneActual != expected)
			throw "standalone OCaml keyword names output mismatch; artifacts: " + root;
		removeTree(root);
		Sys.println("OCAML_KEYWORD_NAMES:PASS");
	}
}
