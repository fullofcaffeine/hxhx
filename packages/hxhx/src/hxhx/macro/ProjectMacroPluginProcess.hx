package hxhx.macro;

import haxe.io.Eof;

/** Exit code and merged standard output and error of one finished tool run. */
typedef ProjectMacroPluginProcessResult = {
	final code:Int;
	final output:String;
}

/**
	Runs the external tools of a project-macro plugin build (the child hxhx, `dune`, `ocamlopt`).

	Why
	- The build reads each tool's output (the child compiler reports its library and sources; a
	  failure needs the tool's own message). Reading standard output to its end while the tool
	  fills an unread standard-error pipe would block both processes, and `dune` writes many
	  warnings to standard error. Merging the two streams before the tool starts avoids that.

	What
	- `run(program, args)` returns the exit code and the merged output. A program that cannot be
	  started reports exit code 127, as a POSIX shell does, instead of throwing.
	- On POSIX hosts the tool runs through `/bin/sh -c 'exec "$0" "$@" 2>&1'`, which passes every
	  argument unchanged. On Windows the streams are read one after the other.
**/
class ProjectMacroPluginProcess {
	public static function run(program:String, args:Array<String>):ProjectMacroPluginProcessResult {
		final windows = Sys.systemName() == "Windows";
		final process = try {
			windows ? new sys.io.Process(program, args) : new sys.io.Process("/bin/sh", ["-c", 'exec "$0" "$@" 2>&1', program].concat(args));
		} catch (error:String) {
			return {code: 127, output: "could not start `" + program + "`: " + error};
		} catch (error:haxe.Exception) {
			return {code: 127, output: "could not start `" + program + "`: " + error.message};
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
		return {code: code, output: output.toString()};
	}

	/** The last `count` non-empty lines of `output`, for failure messages. */
	public static function tail(output:String, count:Int):String {
		final lines = [for (line in output.split("\n")) if (StringTools.trim(line).length > 0) line];
		return lines.slice(lines.length > count ? lines.length - count : 0).join("\n");
	}
}
