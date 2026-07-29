import haxe.io.Path;
import reflaxe.ocaml.tooling.AuthoringBuildOptions;
import reflaxe.ocaml.tooling.AuthoringFileStamp;
import reflaxe.ocaml.tooling.AuthoringHost;
import reflaxe.ocaml.tooling.ReflaxeOcamlAuthoring;

using StringTools;

/** Proves fresh-process build, watch, run, and fail-closed authoring behavior. **/
class AuthoringFixture {
	static function main():Void {
		testOneShotBuildAndRun();
		testWatchRebuildsOneStableSourceChange();
		testBuildFailureIsReturned();
		testMissingHxmlFailsBeforeProcessStart();
		Sys.println("REFLAXE_OCAML_AUTHORING_FIXTURE:PASS");
	}

	static function testOneShotBuildAndRun():Void {
		final host = healthyHost();
		host.file("/project/out/app.exe", "binary", 1);
		host.exitCodes = [0, 0];
		final options = defaultOptions(false, null, "out/app.exe", ["--smoke"]);
		final exitCode = ReflaxeOcamlAuthoring.run(host, "/project", options);
		assert(exitCode == 0, "one-shot build/run failed");
		assert(host.commands.length == 2, "one-shot build/run command count changed");
		assert(host.commands[0].command == "haxe" && host.commands[0].args[0] == "/project/build.hxml", "Haxe build command changed");
		assert(host.commands[0].args.contains("reflaxe_output_transaction"), "Haxe build did not request atomic generated-source publication");
		assert(host.commands[0].args.contains("ocaml_build_timing_report"), "Haxe build did not request native timing evidence");
		assert(host.commands[1].command == "/project/out/app.exe"
			&& host.commands[1].args[0] == "--smoke", "artifact run command changed");
		assert(host.stdout.contains("REFLAXE_OCAML_BUILD:PASS"), "build pass marker missing");
		assert(host.stdout.contains("REFLAXE_OCAML_RUN:PASS"), "run pass marker missing");
	}

	static function testWatchRebuildsOneStableSourceChange():Void {
		final host = healthyHost();
		host.exitCodes = [0, 0];
		host.changeSourceOnSleep = 1;
		final options = defaultOptions(true, 2);
		final exitCode = ReflaxeOcamlAuthoring.run(host, "/project", options);
		assert(exitCode == 0, "bounded watch failed");
		assert(host.commands.length == 2, "generated output caused an extra watch rebuild");
		assert(host.stdout.contains("1 input changed: src/Main.hx"), "changed source explanation missing");
		assert(host.stdout.contains("fresh Haxe process; unchanged output preserves downstream build caches"), "safe watch policy missing");
	}

	static function testBuildFailureIsReturned():Void {
		final host = healthyHost();
		host.exitCodes = [7];
		final exitCode = ReflaxeOcamlAuthoring.run(host, "/project", defaultOptions());
		assert(exitCode == 7, "build failure exit code was hidden");
		assert(host.stdout.contains("REFLAXE_OCAML_BUILD:FAIL"), "build failure marker missing");
		assert(host.stderr.contains("failed (exit 7"), "build failure explanation missing");
	}

	static function testMissingHxmlFailsBeforeProcessStart():Void {
		final host = healthyHost();
		final options = defaultOptions(false, null, null, [], "missing.hxml");
		final exitCode = ReflaxeOcamlAuthoring.run(host, "/project", options);
		assert(exitCode == 2, "missing HXML did not return usage failure");
		assert(host.commands.length == 0, "missing HXML still started a process");
	}

	static function healthyHost():FakeAuthoringHost {
		final host = new FakeAuthoringHost();
		host.directory("/project", ["build.hxml", "src"]);
		host.directory("/project/src", ["Main.hx"]);
		host.file("/project/build.hxml", "-cp src\n-main Main\n", 1);
		host.file("/project/src/Main.hx", "class Main {}\n", 1);
		return host;
	}

	static function defaultOptions(watch:Bool = false, maxBuilds:Null<Int> = null, runArtifact:Null<String> = null, ?runArguments:Array<String>,
			hxmlPath:String = "build.hxml"):AuthoringBuildOptions {
		return {
			hxmlPath: hxmlPath,
			outputPath: "out",
			watch: watch,
			watchPaths: [],
			pollMilliseconds: 10,
			debounceMilliseconds: 5,
			maxBuilds: maxBuilds,
			runArtifact: runArtifact,
			runArguments: runArguments == null ? [] : runArguments
		};
	}

	static function assert(condition:Bool, message:String):Void {
		if (!condition) {
			throw message;
		}
	}
}

private typedef FakeFile = {
	var contents:String;
	var modifiedMilliseconds:Float;
	var size:Float;
}

private class FakeAuthoringHost implements AuthoringHost {
	final files:Map<String, FakeFile> = [];
	final directories:Map<String, Array<String>> = [];

	public final commands = new Array<{command:String, args:Array<String>, workingDirectory:String}>();
	public var exitCodes = new Array<Int>();
	public var changeSourceOnSleep:Null<Int> = null;
	public var stdout = "";
	public var stderr = "";

	var timeMilliseconds = 1000.0;
	var sleepCount = 0;

	public function new() {}

	public function file(path:String, contents:String, modifiedMilliseconds:Float):Void {
		files.set(normalize(path), {
			contents: contents,
			modifiedMilliseconds: modifiedMilliseconds,
			size: contents.length
		});
	}

	public function directory(path:String, entries:Array<String>):Void {
		final sorted = entries.copy();
		sorted.sort(compareStrings);
		directories.set(normalize(path), sorted);
	}

	public function run(command:String, args:Array<String>, workingDirectory:String):Int {
		commands.push({command: command, args: args.copy(), workingDirectory: workingDirectory});
		timeMilliseconds += 25.0;
		if (command == "haxe") {
			file("/project/out/Main.ml", 'generated-${commands.length}', timeMilliseconds);
		}
		final exitCode = exitCodes.shift();
		return exitCode == null ? 0 : exitCode;
	}

	public function exists(path:String):Bool {
		final normalized = normalize(path);
		return files.exists(normalized) || directories.exists(normalized);
	}

	public function isDirectory(path:String):Bool {
		return directories.exists(normalize(path));
	}

	public function readDirectory(path:String):Array<String> {
		final entries = directories.get(normalize(path));
		return entries == null ? [] : entries.copy();
	}

	public function readFile(path:String):Null<String> {
		final value = files.get(normalize(path));
		return value == null ? null : value.contents;
	}

	public function stat(path:String):Null<AuthoringFileStamp> {
		final value = files.get(normalize(path));
		return value == null ? null : {
			modifiedMilliseconds: value.modifiedMilliseconds,
			size: value.size
		};
	}

	public function absolutePath(path:String):String {
		return normalize(Path.isAbsolute(path) ? path : Path.join(["/project", path]));
	}

	public function nowMilliseconds():Float {
		return timeMilliseconds;
	}

	public function sleep(milliseconds:Int):Void {
		timeMilliseconds += milliseconds;
		sleepCount++;
		if (changeSourceOnSleep != null && sleepCount == changeSourceOnSleep) {
			final source = files.get("/project/src/Main.hx");
			if (source != null) {
				source.modifiedMilliseconds += 1.0;
			}
		}
	}

	public function writeStdout(message:String):Void {
		stdout += message;
	}

	public function writeStderr(message:String):Void {
		stderr += message;
	}

	static function normalize(path:String):String {
		return Path.removeTrailingSlashes(Path.normalize(path));
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
