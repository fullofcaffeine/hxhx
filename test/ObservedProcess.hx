/**
	Run a command for a runtime test and report its real exit status, including a death by signal.

	Why
	- Runtime fixtures decide pass or fail from the observed process. Haxe eval's
	  `Process.exitCode()` is not reliable for a child that a signal killed: on Linux CI
	  it reported exit 0 for a SIGFPE crash, and on macOS it throws `process_exit`
	  (`haxe_ocaml-anhiz`). A crash after complete output could then pass.

	How
	- The command runs under `sh`, which writes the command's status as a final stderr
	  marker. A shell reports a signal death as 128 plus the signal number (SIGFPE is 136,
	  SIGKILL is 137). That marker is the status of record.
	- A missing marker or a non-zero status of the shell itself also counts as failure, so
	  a crash can never look like success.
	- With a timeout, the command runs through `timeout` (`gtimeout` on macOS). A timeout
	  reports status 124.
**/
class ObservedProcess {
	static final EXIT_MARKER = "\n__HXHX_OBSERVED_EXIT:";

	/** Standard output of the command. */
	public final stdout:String;

	/** Standard error of the command, without the status marker. */
	public final stderr:String;

	/** Status reported by the shell, or null when the marker is missing. */
	public final code:Null<Int>;

	/** Status of the observing shell itself, or -1 when Haxe could not read it. */
	public final shellCode:Int;

	function new(stdout:String, stderr:String, code:Null<Int>, shellCode:Int) {
		this.stdout = stdout;
		this.stderr = stderr;
		this.code = code;
		this.shellCode = shellCode;
	}

	/** Run `command` with `arguments`, optionally bounded by `timeoutSeconds`. */
	public static function run(command:String, arguments:Array<String>, ?timeoutSeconds:Int):ObservedProcess {
		final commandLine = if (timeoutSeconds == null) {
			[command].concat(arguments);
		} else {
			if (timeoutSeconds <= 0)
				throw "observed process requires a positive timeout";
			[
				Sys.systemName() == "Mac" ? "gtimeout" : "timeout",
				Std.string(timeoutSeconds),
				command
			].concat(arguments);
		}
		final script = '"$$@"; status=$$?; printf "\\n__HXHX_OBSERVED_EXIT:%s" "$$status" >&2';
		final process = new sys.io.Process("sh", ["-c", script, "observe"].concat(commandLine));
		final stdout = process.stdout.readAll().toString();
		final rawStderr = process.stderr.readAll().toString();
		final shellCode = try process.exitCode() catch (_:String) -1;
		process.close();
		final marker = rawStderr.lastIndexOf(EXIT_MARKER);
		final code = marker < 0 ? null : Std.parseInt(rawStderr.substr(marker + EXIT_MARKER.length));
		return new ObservedProcess(stdout, marker < 0 ? rawStderr : rawStderr.substr(0, marker), code, shellCode);
	}

	/** Whether the command exited normally with status 0. */
	public function succeeded():Bool {
		return code == 0 && shellCode == 0;
	}

	/** The status in failure messages, for example `exit=136 shell=0`. */
	public function status():String {
		return "exit=" + (code == null ? "missing" : Std.string(code)) + " shell=" + shellCode;
	}
}
