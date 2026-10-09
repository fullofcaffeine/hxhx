import sys.FileSystem;
import sys.io.File;

/** Black-box trace specification; local compiler acceptance remains a separate required regression. */
class M14TraceUpstreamContract {
	static final root = "test/fixtures/trace_call_contract";

	/** Require a real compiler/runtime exit, retaining failed artifacts for diagnosis. */
	static function command(executable:String, arguments:Array<String>):String {
		final child = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", executable].concat(arguments));
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0 || stderr.length != 0)
			throw "trace observer failed: " + executable + ": " + code + "\n" + stdout + stderr;
		return stdout;
	}

	/** Derive the expected source line from the authored call, independently of generated position records. */
	static function lineOf(module:String, source:String):Int {
		final lines = File.getContent(root + "/" + module + ".hx").split("\n");
		final matches = [
			for (index in 0...lines.length)
				if (StringTools.startsWith(StringTools.trim(lines[index]), source)) index + 1
		];
		if (matches.length != 1)
			throw "trace fixture must contain exactly one source marker: " + source;
		return matches[0];
	}

	static function check(output:String, module:String, target:String, disabled:Bool, expected:String):Void {
		final artifact = output + "/" + module + "-" + target + (disabled ? "-disabled" : "");
		final arguments = ["-cp", root, "-main", module];
		// CLI options are separate arguments; no shell parses authored test data.
		if (disabled) {
			arguments.push("-D");
			arguments.push("no-traces");
		}
		final actual = if (target == "eval") {
			command("node_modules/.bin/haxe", arguments.concat(["--interp"]));
		} else {
			final extension = target == "js" ? ".js" : ".n";
			command("node_modules/.bin/haxe", arguments.concat([target == "js" ? "-js" : "-neko", artifact + extension]));
			command(target == "js" ? "node" : "neko", [artifact + extension]);
		};
		if (actual != expected)
			throw "upstream trace contract differs: " + module + ":" + target + ":disabled=" + disabled + "\n" + actual;
		if (target != "eval")
			FileSystem.deleteFile(artifact + (target == "js" ? ".js" : ".n"));
		Sys.println("TRACE_UPSTREAM_CONTRACT:PASS " + module + ":" + target + ":disabled=" + disabled);
	}

	/** Run inside the caller's unique scratch directory; no output or readiness claim is shared with the local compiler. */
	public static function run(output:String):Void {
		if (StringTools.trim(command("node_modules/.bin/haxe", ["--version"])) != "4.3.7")
			throw "trace contract requires Haxe 4.3.7";
		final positionLine = lineOf("TracePosition", 'trace("value", "extra", 7);');
		final shadowLine = lineOf("TraceShadow", 'trace({');
		for (target in ["eval", "js", "neko"]) {
			check(output, "TraceOrder", target, false, (target == "js" ? "second" : "first") + ":value\nsecond:next\ndone\n");
			check(output, "TraceCallOrder", target, false, "first:value\nsecond:next\n");
			check(output, "TracePosition", target, false, "value:TracePosition:main:" + positionLine + ":extra|7\n");
			check(output, "TraceShadow", target, false, "argument\n" + root + "/TraceShadow.hx:" + shadowLine + ": value\n");
			check(output, "TraceOrder", target, true, "done\n");
			check(output, "TraceShadow", target, true, "");
			check(output, "TraceDisabled", target, true, "");
		}
	}
}
