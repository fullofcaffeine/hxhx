/** Child processes receive logical Array contents, with null preserving shell-command semantics. */
class Main {
	static function main():Void {
		final arguments = ["-c", "printf '%s|%s\\n' \"$1\" \"$#\"", "probe", "space value", "discarded"];
		arguments.pop();
		final process = new sys.io.Process("sh", arguments);
		Sys.println(process.stdout.readLine());
		Sys.println(process.exitCode());
		process.close();
		Sys.println(arguments.length);
		Sys.println(arguments[3]);

		final empty = new sys.io.Process("true", []);
		Sys.println(empty.exitCode());
		empty.close();

		final shell = new sys.io.Process("printf 'via-shell\\n'");
		Sys.println(shell.stdout.readLine());
		Sys.println(shell.exitCode());
		shell.close();
	}
}
