package reflaxe.ocaml.tooling;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

/** Read-only doctor probe backed by the current process environment. **/
class SystemDoctorProbe implements DoctorProbe {
	public function new() {}

	public function run(command:String, args:Array<String>):CommandResult {
		try {
			final process = new Process(command, args);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final processCode = process.exitCode();
			process.close();
			return {
				code: processCode == null ? 1 : processCode,
				stdout: stdout,
				stderr: stderr
			};
		} catch (error:Dynamic) {
			return {
				code: 127,
				stdout: "",
				stderr: Std.string(error)
			};
		}
	}

	public function findExecutable(command:String):Null<String> {
		final rawPath = Sys.getEnv("PATH");
		if (rawPath == null || rawPath.length == 0) {
			return null;
		}
		final isWindows = Sys.systemName() == "Windows";
		final extensions = isWindows ? executableExtensions() : [""];
		for (directory in rawPath.split(isWindows ? ";" : ":")) {
			if (directory.length == 0) {
				continue;
			}
			for (extension in extensions) {
				final candidate = Path.join([directory, command + extension]);
				if (exists(candidate) && !isDirectory(candidate)) {
					return absolutePath(candidate);
				}
			}
		}
		return null;
	}

	function executableExtensions():Array<String> {
		final raw = Sys.getEnv("PATHEXT");
		if (raw == null || raw.length == 0) {
			return ["", ".exe", ".cmd", ".bat"];
		}
		return [""].concat([for (extension in raw.split(";")) extension.toLowerCase()]);
	}

	public function exists(path:String):Bool {
		try {
			return FileSystem.exists(path);
		} catch (_:Dynamic) {
			return false;
		}
	}

	public function isDirectory(path:String):Bool {
		try {
			return FileSystem.isDirectory(path);
		} catch (_:Dynamic) {
			return false;
		}
	}

	public function readDirectory(path:String):Array<String> {
		try {
			final entries = FileSystem.readDirectory(path);
			entries.sort(compareStrings);
			return entries;
		} catch (_:Dynamic) {
			return [];
		}
	}

	public function readFile(path:String):Null<String> {
		try {
			return File.getContent(path);
		} catch (_:Dynamic) {
			return null;
		}
	}

	public function absolutePath(path:String):String {
		return FileSystem.absolutePath(path);
	}

	public function systemName():String {
		return Sys.systemName();
	}

	public function environment(name:String):Null<String> {
		return Sys.getEnv(name);
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
