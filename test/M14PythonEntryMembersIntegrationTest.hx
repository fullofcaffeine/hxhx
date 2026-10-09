import backend.BackendContext;
import backend.source.SourceTargetCommon;
import backend.source.SourceNativeTarget;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Compares Python entry-class static members with upstream Haxe. */
class M14PythonEntryMembersIntegrationTest {
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
		final fixture = "test/python_entry_members";
		final expected = File.getContent(fixture + "/expected.stdout");
		if (run("haxe", ["-cp", fixture, "--run", "Main"]) != expected)
			throw "upstream Python entry-class static members contract differs from its authored expectation";
		final path = fixture + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader([fixture], new StringMap<String>(), index, function(_) return false);
		loader.markResolvedAlready([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index, loader);
		final root = Path.normalize(Sys.getCwd() + "/.tmp/python_entry_members_" + Std.string(Date.now().getTime()));
		FileSystem.createDirectory(root);
		final context = new BackendContext(root, root + "/out.py", "Main", true, false, new StringMap<String>());
		final emitted = SourceTargetCommon.emitTarget(SourceNativeTarget.Python, new MacroExpandedProgram([typed], false), context);
		final actual = run("python3", [emitted.entryPath]);
		File.saveContent(root + "/actual.stdout", actual);
		if (actual != expected)
			throw "native Python entry-class static members output mismatch; artifacts: " + root;
		removeTree(root);
		Sys.println("PYTHON_ENTRY_MEMBERS:PASS");
	}
}
