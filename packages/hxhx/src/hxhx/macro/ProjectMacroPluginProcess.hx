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
	  that cannot be started reports a non-zero exit code instead of throwing. When the limit passes
	  (600 s unless the caller says otherwise; plugin builds pass `HXHX_MACRO_PLUGIN_BUILD_TIMEOUT`,
	  1800 s by default, and the toolchain checks keep 600 s), the tool's whole process group gets
	  `SIGTERM`, then `SIGKILL` five seconds later, and the result has `timedOut`.
	- On POSIX hosts the tool runs under `/bin/sh` (see `watchedScript`), which passes every
	  argument unchanged, merges standard error into standard output, runs the tool in its own
	  process group, forwards SIGINT/SIGTERM/SIGHUP to that group, and runs a one-second watchdog
	  loop beside it. The watchdog writes a marker file before stopping the tool, so a timeout is
	  never confused with the tool's own exit code.
	- `isAlive(pid)` asks `kill -0` whether a process exists; it never sends a signal.

	Gotchas
	- On Windows the tool runs directly, without the time limit or group signals, and its two
	  streams are read one after the other. A tool that fills its unread standard-error pipe there
	  blocks the build.
	- A host whose `/bin/sh` has neither `setsid` nor working `set -m` job control cannot give the
	  tool its own group; the wrapper then signals only the tool itself, and processes the tool
	  started can outlive a timeout or an interrupt.
	- Killing only the parent hxhx process (for example `kill -INT <hxhx pid>` while the wrapper
	  keeps running) does not reach the wrapper; Ctrl-C does, because the terminal signals the whole
	  foreground group, which contains the wrapper.
	- A compile cancelled by a compilation-server request does not stop a running tool; the tool
	  is bounded only by its time limit.
**/
class ProjectMacroPluginProcess {
	/**
		The POSIX wrapper: `$1` marker file, `$2` limit in seconds, then the tool and its arguments.

		The tool starts in its own process group (`setsid` where it exists, otherwise `set -m` job
		control), so one signal reaches it and every process it started. SIGINT, SIGTERM, or SIGHUP
		to the wrapper (for example Ctrl-C on the compile) is forwarded to that group as SIGTERM,
		then SIGKILL two seconds later. The watchdog does the same at the limit after writing the
		marker. When the tool exits, any process it left in its group is stopped too, so no
		grandchild keeps the output pipe open.

		The group is signalled as `kill -SIG -PGID`, without `--`: dash (`/bin/sh` on Debian and
		Ubuntu) rejects `--` as an illegal number, which would leave the group running.
	**/
	static function watchedScript():String
		return "marker=\"$1\"; limit=\"$2\"; shift 2\nif command -v setsid >/dev/null 2>&1; then setsid \"$@\" 2>&1 & else set -m; \"$@\" 2>&1 & fi\nchild=$!\nstop() { kill -\"$1\" \"-$child\" 2>/dev/null || kill -\"$1\" \"$child\" 2>/dev/null; }\ntrap 'stop TERM; sleep 2; stop KILL; exit 130' INT\ntrap 'stop TERM; sleep 2; stop KILL; exit 143' TERM HUP\n( elapsed=0\n  while kill -0 \"$child\" 2>/dev/null; do\n    if [ \"$elapsed\" -ge \"$limit\" ]; then : > \"$marker\"; stop TERM; sleep 5; stop KILL; break; fi\n    sleep 1; elapsed=$((elapsed + 1))\n  done ) >/dev/null 2>&1 &\nwhile :; do wait \"$child\"; status=$?; kill -0 \"$child\" 2>/dev/null || break; done\nstop TERM\nexit \"$status\"";

	/** A started wrapper: the process (its id is the wrapper shell's) and its timeout marker file. */
	public static function launch(program:String, args:Array<String>, timeoutSeconds:Float):{process:sys.io.Process, marker:String} {
		final temporary = Sys.getEnv("TMPDIR");
		final marker = haxe.io.Path.join([
			temporary == null || temporary.length == 0 ? "/tmp" : temporary,
			"hxhx-tool-timeout-" + haxe.crypto.Sha256.encode(Sys.time() + ":" + Std.random(0x3fffffff)).substr(0, 12)
		]);
		final limit = Std.string(Math.max(1, Math.ceil(timeoutSeconds)));
		final process = Sys.systemName() == "Windows" ? new sys.io.Process(program,
			args) : new sys.io.Process("/bin/sh", ["-c", watchedScript(), "sh", marker, limit, program].concat(args));
		return {process: process, marker: marker};
	}

	/** Read a launched wrapper to its end and return the result. */
	public static function finish(started:{process:sys.io.Process, marker:String}):ProjectMacroPluginProcessResult {
		final process = started.process;
		final output = new StringBuf();
		try {
			while (true) {
				output.add(process.stdout.readLine());
				output.add("\n");
			}
		} catch (_:Eof) {}
		if (Sys.systemName() == "Windows")
			output.add(process.stderr.readAll().toString());
		final code = process.exitCode();
		process.close();
		final timedOut = sys.FileSystem.exists(started.marker);
		if (timedOut)
			sys.FileSystem.deleteFile(started.marker);
		return {code: code, output: output.toString(), timedOut: timedOut};
	}

	public static function run(program:String, args:Array<String>, timeoutSeconds:Float = 600.0):ProjectMacroPluginProcessResult {
		final started = try {
			launch(program, args, timeoutSeconds);
		} catch (error:String) {
			return {code: 127, output: "could not start `" + program + "`: " + error, timedOut: false};
		} catch (error:haxe.Exception) {
			return {code: 127, output: "could not start `" + program + "`: " + error.message, timedOut: false};
		}
		return finish(started);
	}

	/**
		Whether a process with this id exists; always `true` on Windows.

		`kill -0` succeeds for a live process of this user and fails with "Operation not permitted"
		for a live process of another user; both count as alive, so a lock is never treated as stale
		merely because its id now belongs to someone else's process.
	**/
	public static function isAlive(pid:Int):Bool {
		if (Sys.systemName() == "Windows")
			return true;
		final probe = run("kill", ["-0", Std.string(pid)], 10.0);
		return probe.code == 0 || probe.output.toLowerCase().indexOf("not permitted") >= 0;
	}

	/** The last `count` non-empty lines of `output`, for failure messages. */
	public static function tail(output:String, count:Int):String {
		final lines = [for (line in output.split("\n")) if (StringTools.trim(line).length > 0) line];
		return lines.slice(lines.length > count ? lines.length - count : 0).join("\n");
	}
}
