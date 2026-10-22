import backend.BackendContext;
import backend.vm.NekoTargetCore;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Executes authored default-argument expectations with upstream Haxe and both native Neko layouts. */
class M14NekoDefaultArgumentsIntegrationTest {
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

	static function main():Void {
		final fixture = "test/neko_default_arguments";
		final expected = File.getContent(fixture + "/expected.stdout");
		final root = Path.normalize(Sys.getCwd() + "/.tmp/neko_default_arguments_" + Std.string(Date.now().getTime()));
		FileSystem.createDirectory(root);
		run("haxe", ["-cp", fixture, "-main", "Main", "-neko", root + "/upstream.n"]);
		if (run("neko", [root + "/upstream.n"]) != expected)
			throw "upstream default-argument output changed; artifacts: " + root;
		final parsed = ParserStage.parse(File.getContent(fixture + "/Main.hx"), fixture + "/Main.hx");
		final resolved = new ResolvedModule("Main", fixture + "/Main.hx", parsed);
		final program = MacroStage.expandProgram([TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]))], []);
		final context = new BackendContext(root, root + "/main.n", "Main", true, false, new StringMap<String>());
		final split = @:privateAccess NekoTargetCore.renderSplitProgram(program, context, root + "/main.neko");
		File.saveContent(root + "/main.neko", split.entrySource);
		for (part in split.support)
			File.saveContent(part.path, part.source);
		final single = @:privateAccess NekoTargetCore.renderProgram(program, context);
		if (single.indexOf("__hxhx_symbols.Main_observe = function(label, number)") < 0)
			throw "required single-file parameters lost their fixed-arity function; artifacts: " + root;
		File.saveContent(root + "/single.neko", single);
		for (file in FileSystem.readDirectory(root))
			if (StringTools.endsWith(file, ".neko"))
				run("nekoc", [root + "/" + file]);
		for (layout in ["main", "single"]) {
			final actual = run("neko", [root + "/" + layout + ".n"]);
			if (actual != expected)
				throw "default arguments differ in " + layout + "; artifacts: " + root;
			Sys.println("NEKO_DEFAULT_ARGUMENTS:PASS layout=" + layout);
		}
		for (file in FileSystem.readDirectory(root))
			FileSystem.deleteFile(root + "/" + file);
		FileSystem.deleteDirectory(root);
	}
}
