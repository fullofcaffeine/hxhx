import backend.BackendContext;
import backend.BackendRegistry;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.io.File;
import sys.io.Process;

/** Compares authored console output with upstream Haxe and executes generated PHP. */
class M14PhpConsoleOutputIntegrationTest {
	static function run(command:String, arguments:Array<String>):String {
		final child = new Process(command, arguments);
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0)
			throw command + " failed: " + stderr;
		return StringTools.replace(stdout, "\r\n", "\n");
	}

	static function main():Void {
		final source = "test/php_console_output/src";
		final root = ".tmp/m14_php_console_output_" + Std.string(Date.now().getTime());
		final native = Sys.command("sh", ["-c", "command -v php >/dev/null 2>&1"]) == 0;
		for (name in ["Main", "TraceValues"]) {
			final expected = name == "Main" ? File.getContent("test/php_console_output/expected.stdout") : "true\nfalse\n";
			var upstream = run("haxe", ["-cp", source, "-main", name, "--interp"]);
			// Only the trace payload is in scope; PHP currently omits source-position prefixes.
			if (name == "TraceValues")
				upstream = ~/^(test\/php_console_output\/src\/)?TraceValues\.hx:[0-9]+: /gm.replace(upstream, "");
			if (upstream != expected)
				throw "upstream console expectation differs for " + name + ":\n" + upstream;
			final path = Path.join([source, name + ".hx"]);
			final resolved = new ResolvedModule(name, path, ParserStage.parse(File.getContent(path), path));
			final program = MacroStage.expandProgram([TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]))], []);
			final result = BackendRegistry.requireForTarget("php-native")
				.emit(program, new BackendContext(Path.join([root, name]), null, name, true, false, new StringMap<String>()));
			if (native) {
				final actual = run("php", [result.entryPath]);
				if (actual != expected)
					throw "PHP console output differs for " + name + ":\n" + actual;
				if (name == "Main") {
					final upstreamOutput = Path.join([root, "upstream"]);
					run("haxe", ["-cp", source, "-main", name, "--php", upstreamOutput]);
					if (run("php", [Path.join([upstreamOutput, "index.php"])]) != expected)
						throw "upstream PHP console expectation differs";
				}
			}
		}
		Sys.println(native ? "PHP_CONSOLE_OUTPUT:PASS native" : "PHP_CONSOLE_OUTPUT:PASS source only; PHP unavailable");
	}
}
