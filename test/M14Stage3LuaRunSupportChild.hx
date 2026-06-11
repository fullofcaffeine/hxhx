import backend.EmitResult;
import haxe.io.Path;
import hxhx.Stage3RunSupport;
import sys.FileSystem;
import sys.io.File;

class M14Stage3LuaRunSupportChild {
	static function rmrf(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (name in FileSystem.readDirectory(path))
				rmrf(Path.join([path, name]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function mkdirp(path:String):Void {
		if (FileSystem.exists(path))
			return;
		final parent = Path.directory(path);
		if (parent != null && parent.length > 0 && parent != path)
			mkdirp(parent);
		FileSystem.createDirectory(path);
	}

	static function main():Void {
		final mode = Sys.getEnv("HXHX_LUA_RUN_SUPPORT_MODE") ?? "";
		final tmp = Path.normalize(".tmp/m14_stage3_lua_run_support_child_" + mode + "_" + Std.string(Std.int(Date.now().getTime())));
		final bin = Path.join([tmp, "bin"]);
		final oldPath = Sys.getEnv("PATH");
		try {
			mkdirp(bin);
			final absBin = FileSystem.fullPath(bin);
			final fakeLua = Path.join([absBin, "lua"]);
			File.saveContent(fakeLua, "#!/usr/bin/env sh\nprintf '%s\\n' \"lua-stdout:$*\"\n");
			final chmodCode = Sys.command("chmod", ["+x", fakeLua]);
			if (chmodCode != 0)
				throw "failed to chmod fake lua";
			Sys.putEnv("PATH", absBin + ":" + (oldPath == null ? "" : oldPath));

			switch (mode) {
				case "cmd":
					final err = Stage3RunSupport.runCommandOnlyUnit(true, ["lua runner.lua alpha"], tmp);
					if (err != null)
						throw err;
				case "run":
					final emitted = new EmitResult("artifact.lua", [], false);
					final err = Stage3RunSupport.runEmittedArtifact("lua-native", false, [], true, ["alpha", "beta"], tmp, emitted, false);
					if (err != null)
						throw err;
				case _:
					throw "unknown mode: " + mode;
			}
		} catch (e:haxe.Exception) {
			Sys.putEnv("PATH", oldPath == null ? "" : oldPath);
			rmrf(tmp);
			throw e.message;
		} catch (raw:String) {
			Sys.putEnv("PATH", oldPath == null ? "" : oldPath);
			rmrf(tmp);
			throw raw;
		}
		Sys.putEnv("PATH", oldPath == null ? "" : oldPath);
		rmrf(tmp);
	}
}
