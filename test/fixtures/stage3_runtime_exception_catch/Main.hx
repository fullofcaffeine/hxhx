/**
	Catches failed file-system calls and prints what each handler receives.

	The OCaml runtime reports these failures with OCaml exceptions such as
	`Sys_error`. Haxe code must still catch them as `String` messages through
	`Dynamic`, `String`, and `haxe.Exception` handlers, with the same text as
	upstream Haxe. A handler for another type must let the failure reach an
	outer handler, and `return` and `break` inside a `try` must keep working.
**/
class Main {
	static final scratch = ".tmp/stage3_runtime_exception_catch_scratch";

	static function readOrFallback(path:String):String {
		try {
			return sys.io.File.getContent(path);
		} catch (e:Dynamic) {
			return "fallback";
		}
	}

	static function firstReadable(paths:Array<String>):String {
		for (path in paths) {
			try {
				return sys.io.File.getContent(path);
			} catch (e:String) {}
		}
		return "none";
	}

	static function main():Void {
		if (!sys.FileSystem.exists(scratch))
			sys.FileSystem.createDirectory(scratch);
		final file = scratch + "/present.txt";
		sys.io.File.saveContent(file, "present");
		final missing = scratch + "/missing.txt";

		try {
			sys.io.File.getContent(missing);
			Sys.println("read");
		} catch (e:Dynamic) {
			Sys.println("dynamic: " + Std.string(e));
		}
		try {
			sys.io.File.getContent(missing);
		} catch (e:String) {
			Sys.println("string: " + e);
		}
		try {
			sys.io.File.getContent(missing);
		} catch (e:haxe.Exception) {
			// `Std.string(e)` on an exception object is owned by haxe_ocaml-czx3v.
			Sys.println("exception: " + e.message + " / " + e.toString());
		}
		try {
			throw "plain";
		} catch (e:haxe.Exception) {
			Sys.println("thrown string as exception: " + e.message);
		}
		try {
			try {
				sys.io.File.getContent(missing);
			} catch (e:Int) {
				Sys.println("int: " + e);
			}
		} catch (e:String) {
			Sys.println("outer: " + e);
		}
		Sys.println("fallback: " + readOrFallback(missing));
		Sys.println("first readable: " + firstReadable([missing, file]));
		for (attempt in 0...3) {
			try {
				if (attempt == 1)
					break;
				sys.io.File.getContent(missing);
			} catch (e:Dynamic) {
				Sys.println("attempt " + attempt + " failed");
			}
		}

		try {
			sys.io.File.getContent(scratch);
		} catch (e:Dynamic) {
			Sys.println("directory read: " + Std.string(e));
		}
		try {
			sys.FileSystem.deleteDirectory(scratch + "/missing-dir");
		} catch (e:Dynamic) {
			Sys.println("rmdir missing: " + Std.string(e));
		}
		try {
			sys.FileSystem.deleteDirectory(file);
		} catch (e:Dynamic) {
			Sys.println("rmdir file: " + Std.string(e));
		}
		try {
			sys.FileSystem.rename(missing, scratch + "/other.txt");
		} catch (e:Dynamic) {
			Sys.println("rename: " + Std.string(e));
		}
		try {
			sys.io.File.saveContent(scratch + "/missing-dir/x.txt", "x");
		} catch (e:Dynamic) {
			Sys.println("save: " + Std.string(e));
		}
		try {
			sys.io.File.copy(missing, scratch + "/copy.txt");
		} catch (e:Dynamic) {
			Sys.println("copy: " + Std.string(e));
		}
		try {
			sys.FileSystem.deleteFile(missing);
		} catch (e:Dynamic) {
			Sys.println("delete: " + Std.string(e));
		}
		try {
			sys.FileSystem.readDirectory(scratch + "/missing-dir");
		} catch (e:Dynamic) {
			Sys.println("list missing: " + Std.string(e));
		}
		try {
			sys.FileSystem.readDirectory(file);
		} catch (e:Dynamic) {
			Sys.println("list file: " + Std.string(e));
		}
		try {
			sys.FileSystem.fullPath(missing);
		} catch (e:Dynamic) {
			Sys.println("full path: " + Std.string(e));
		}
		try {
			Sys.setCwd(scratch + "/missing-dir");
		} catch (e:Dynamic) {
			Sys.println("set cwd: " + Std.string(e));
		}
		sys.FileSystem.createDirectory(file);
		Sys.println("create existing file: ok");
		try {
			sys.FileSystem.createDirectory(file + "/sub/deeper");
		} catch (e:Dynamic) {
			Sys.println("create below file: " + Std.string(e));
		}

		sys.FileSystem.deleteFile(file);
		sys.FileSystem.deleteDirectory(scratch);
	}
}
