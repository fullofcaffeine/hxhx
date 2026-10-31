package hxhx.macro;

import haxe.io.Eof;

/** Exit code and merged standard output and error of one finished tool run. */
typedef ProjectMacroPluginProcessResult = {
	final code:Int;
	final output:String;

	/** The tool ran past its time limit and was stopped. */
	final timedOut:Bool;
}

/**
	Runs the external tools of a project-macro plugin build (the child hxhx, `dune`, `ocamlopt`).

	Why
	- The build reads each tool's output (the child compiler reports its library and sources; a
	  failure needs the tool's own message). Reading standard output to its end while the tool
	  fills an unread standard-error pipe would block both processes, and `dune` writes many
	  warnings to standard error. Merging the two streams before the tool starts avoids that.
	- A tool that hangs must not hang the compile, so each run has a wall-clock limit.

	What
	- `run(program, args, timeoutSeconds)` returns the exit code and the merged output. A program
	  that cannot be started reports exit code 127, as a POSIX shell does, instead of throwing. When
	  the limit passes, the tool gets `SIGTERM` (then `SIGKILL` five seconds later) and the result
	  has `timedOut`.
	- On POSIX hosts the tool runs under `/bin/sh`, which passes every argument unchanged, merges
	  standard error into standard output, and runs a one-second watchdog loop beside the tool. The
	  watchdog writes a marker file before stopping the tool, so a timeout is never confused with
	  the tool's own exit code.
	- `isAlive(pid)` asks `kill -0` whether a process exists; it never sends a signal.

	Gotchas
	- On Windows the tool runs directly, without the time limit, and its two streams are read one
	  after the other. A tool that fills its unread standard-error pipe there blocks the build.
	- A compile cancelled by a compilation-server request does not stop a running tool; the tool
	  is bounded only by its time limit.
**/
class ProjectMacroPluginProcess {
	/** The POSIX wrapper: `$1` marker file, `$2` limit in seconds, then the tool and its arguments. */
	static final WATCHED = "marker=\"$1\"; limit=\"$2\"; shift 2; \"$@\" 2>&1 & child=$!; ( elapsed=0; while kill -0 \"$child\" 2>/dev/null; do if [ \"$elapsed\" -ge \"$limit\" ]; then : > \"$marker\"; kill -TERM \"$child\" 2>/dev/null; sleep 5; kill -KILL \"$child\" 2>/dev/null; break; fi; sleep 1; elapsed=$((elapsed + 1)); done ) >/dev/null 2>&1 & wait \"$child\"; exit \"$?\"";

	public static function run(program:String, args:Array<String>, timeoutSeconds:Float = 600.0):ProjectMacroPluginProcessResult {
		final windows = Sys.systemName() == "Windows";
		final temporary = Sys.getEnv("TMPDIR");
		final marker = haxe.io.Path.join([
			temporary == null || temporary.length == 0 ? "/tmp" : temporary,
			"hxhx-tool-timeout-" + haxe.crypto.Sha256.encode(Sys.time() + ":" + Std.random(0x3fffffff)).substr(0, 12)
		]);
		final limit = Std.string(Math.max(1, Math.ceil(timeoutSeconds)));
		final process = try {
			windows ? new sys.io.Process(program, args) : new sys.io.Process("/bin/sh", ["-c", WATCHED, "sh", marker, limit, program].concat(args));
		} catch (error:String) {
			return {code: 127, output: "could not start `" + program + "`: " + error, timedOut: false};
		} catch (error:haxe.Exception) {
			return {code: 127, output: "could not start `" + program + "`: " + error.message, timedOut: false};
		}
		final output = new StringBuf();
		try {
			while (true) {
				output.add(process.stdout.readLine());
				output.add("\n");
			}
		} catch (_:Eof) {}
		if (windows)
			output.add(process.stderr.readAll().toString());
		final code = process.exitCode();
		process.close();
		final timedOut = sys.FileSystem.exists(marker);
		if (timedOut)
			sys.FileSystem.deleteFile(marker);
		return {code: code, output: output.toString(), timedOut: timedOut};
	}

	/** Whether a process with this id exists (POSIX `kill -0`); always `true` on Windows. */
	public static function isAlive(pid:Int):Bool {
		if (Sys.systemName() == "Windows")
			return true;
		return run("kill", ["-0", Std.string(pid)], 10.0).code == 0;
	}

	/** The last `count` non-empty lines of `output`, for failure messages. */
	public static function tail(output:String, count:Int):String {
		final lines = [for (line in output.split("\n")) if (StringTools.trim(line).length > 0) line];
		return lines.slice(lines.length > count ? lines.length - count : 0).join("\n");
	}
}
