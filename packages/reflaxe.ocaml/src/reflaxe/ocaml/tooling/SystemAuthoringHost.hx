package reflaxe.ocaml.tooling;

import sys.FileSystem;
import sys.io.File;

/** Real streaming process and filesystem host for `build` and `watch`. **/
class SystemAuthoringHost implements AuthoringHost {
	public function new() {}

	/**
		Runs one child with inherited stdio and a project working directory.

		Haxelib marks the CLI process with `HAXELIB_RUN`. Those markers are
		temporarily removed so a child Haxe compilation registers the OCaml target
		normally instead of mistaking itself for the package runner.
	**/
	public function run(command:String, args:Array<String>, workingDirectory:String):Int {
		final originalDirectory = Sys.getCwd();
		final haxelibRun = Sys.getEnv("HAXELIB_RUN");
		final haxelibRunName = Sys.getEnv("HAXELIB_RUN_NAME");
		var changedDirectory = false;
		try {
			Sys.setCwd(workingDirectory);
			changedDirectory = true;
			Sys.putEnv("HAXELIB_RUN", null);
			Sys.putEnv("HAXELIB_RUN_NAME", null);
			final exitCode = Sys.command(command, args);
			restoreProcessState(originalDirectory, changedDirectory, haxelibRun, haxelibRunName);
			return exitCode;
		} catch (error:Dynamic) {
			restoreProcessState(originalDirectory, changedDirectory, haxelibRun, haxelibRunName);
			writeStderr('Could not run $command: ${Std.string(error)}\n');
			return 127;
		}
	}

	function restoreProcessState(originalDirectory:String, changedDirectory:Bool, haxelibRun:Null<String>, haxelibRunName:Null<String>):Void {
		Sys.putEnv("HAXELIB_RUN", haxelibRun);
		Sys.putEnv("HAXELIB_RUN_NAME", haxelibRunName);
		if (changedDirectory) {
			try {
				Sys.setCwd(originalDirectory);
			} catch (_:Dynamic) {}
		}
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

	public function stat(path:String):Null<AuthoringFileStamp> {
		try {
			final value = FileSystem.stat(path);
			return {
				modifiedMilliseconds: value.mtime.getTime(),
				size: value.size
			};
		} catch (_:Dynamic) {
			return null;
		}
	}

	public function absolutePath(path:String):String {
		return FileSystem.absolutePath(path);
	}

	public function nowMilliseconds():Float {
		return Sys.time() * 1000.0;
	}

	public function sleep(milliseconds:Int):Void {
		Sys.sleep(milliseconds / 1000.0);
	}

	public function writeStdout(message:String):Void {
		Sys.stdout().writeString(message);
		Sys.stdout().flush();
	}

	public function writeStderr(message:String):Void {
		Sys.stderr().writeString(message);
		Sys.stderr().flush();
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
