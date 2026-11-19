/**
	A runtime observation must fail when a signal kills the observed process,
	even when the process already printed the expected output.

	Why
	- `M14Stage3RuntimeFixture.observe` decides pass or fail for many native
	  runtime tests. On Linux CI it once reported `exit=0` for a process killed
	  by SIGFPE (`haxe_ocaml-anhiz`), and on macOS Haxe eval throws
	  `process_exit` instead. A crash after complete output could then pass on
	  one platform and fail with an unrelated error on the other.
	- The observation must report its own failure, with the signal status, on
	  every platform.
**/
class M14RuntimeObservationSignalTest {
	static function expectFailure(label:String, script:String, expected:String, needle:String):Void {
		var message:Null<String> = null;
		try {
			M14Stage3RuntimeFixture.observe({command: "sh", arguments: ["-c", script], expected: expected});
		} catch (e:String) {
			message = e;
		}
		if (message == null)
			throw label + ": observation accepted a failed process";
		if (message.indexOf("runtime fixture observation failed") < 0 || message.indexOf(needle) < 0)
			throw label + ": unexpected failure report: " + message;
	}

	static function main():Void {
		M14Stage3RuntimeFixture.observe({command: "sh", arguments: ["-c", "printf ok"], expected: "ok"});
		expectFailure("SIGFPE after complete output", "printf ok; kill -FPE $$", "ok", "exit=136");
		expectFailure("SIGKILL after complete output", "printf ok; kill -KILL $$", "ok", "exit=137");
		expectFailure("ordinary non-zero exit", "printf ok; exit 3", "ok", "exit=3");
		expectFailure("stderr output", "printf ok; printf oops >&2", "ok", "stderr=oops");
		Sys.println("M14_RUNTIME_OBSERVATION_SIGNAL:PASS");
	}
}
