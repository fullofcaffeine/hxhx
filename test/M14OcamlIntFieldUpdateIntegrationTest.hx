import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Builds native OCaml and compares Int field updates with upstream Haxe. */
class M14OcamlIntFieldUpdateIntegrationTest {
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
		final fixture = "test/ocaml_int_field_update";
		final expected = File.getContent(fixture + "/expected.stdout");
		if (run("haxe", ["-cp", fixture, "--run", "Main"]) != expected)
			throw "upstream OCaml Int field updates contract differs from its authored expectation";
		final path = fixture + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final root = Path.normalize(Sys.getCwd() + "/.tmp/ocaml_int_field_update_" + Std.string(Date.now().getTime()));
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), root, true);
		final actual = run(executable, []);
		File.saveContent(root + "/actual.stdout", actual);
		if (actual != expected)
			throw "native OCaml Int field updates output mismatch; artifacts: " + root;
		removeTree(root);
		Sys.println("OCAML_INT_FIELD_UPDATE:PASS");
	}
}
