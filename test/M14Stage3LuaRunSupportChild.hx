import backend.EmitResult;
import haxe.io.Path;
import hxhx.LibraryResolver;
import hxhx.Stage3RunSupport;
import hxhx.Stage3SetupSupport;
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
		final oldNekoPath = Sys.getEnv("NEKOPATH");
		final oldFakeNekoPrintPath = Sys.getEnv("HXHX_FAKE_NEKO_PRINT_PATH");
		final oldHaxelibBin = Sys.getEnv("HAXELIB_BIN");
		final oldLixBin = Sys.getEnv("LIX_BIN");
		try {
			mkdirp(bin);
			final absBin = FileSystem.fullPath(bin);
			final fakeLua = Path.join([absBin, "lua"]);
			File.saveContent(fakeLua, "#!/usr/bin/env sh\nprintf '%s\\n' \"lua-stdout:$*\"\n");
			final fakeNeko = Path.join([absBin, "neko"]);
			File.saveContent(fakeNeko,
				"#!/usr/bin/env sh\nprintf '%s\\n' \"neko-stdout:$*\"\nif [ \"${HXHX_FAKE_NEKO_PRINT_PATH:-}\" = \"1\" ]; then printf '%s\\n' \"neko-path:$NEKOPATH\"; fi\n");
			final chmodCode = Sys.command("chmod", ["+x", fakeLua]);
			if (chmodCode != 0)
				throw "failed to chmod fake lua";
			final chmodNekoCode = Sys.command("chmod", ["+x", fakeNeko]);
			if (chmodNekoCode != 0)
				throw "failed to chmod fake neko";
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
				case "neko-cmd":
					mkdirp(Path.join([tmp, "bin"]));
					final emitted = new EmitResult(Path.join([tmp, "bin", "main.n"]), [], false);
					final err = Stage3RunSupport.runEmittedArtifact("neko-native", true, ["neko bin/main.n"], false, [], tmp, emitted, false);
					if (err != null)
						throw err;
				case "neko-cmd-path":
					mkdirp(Path.join([tmp, "bin"]));
					Sys.putEnv("NEKOPATH", "existing-neko-path");
					Sys.putEnv("HXHX_FAKE_NEKO_PRINT_PATH", "1");
					final emitted = new EmitResult(Path.join([tmp, "bin", "main.n"]), [], false);
					final err = Stage3RunSupport.runEmittedArtifact("neko-native", true, ["neko bin/main.n"], false, [], tmp, emitted, false,
						["lib/ndll/Linux64/"]);
					Sys.putEnv("HXHX_FAKE_NEKO_PRINT_PATH", "");
					if (err != null)
						throw err;
					if (Sys.getEnv("NEKOPATH") != "existing-neko-path")
						throw "NEKOPATH was not restored";
				case "collect-neko-ndll":
					final libRoot = Path.join([tmp, "dummy_ndll"]);
					final src = Path.join([libRoot, "src"]);
					final ndll = Path.join([libRoot, "ndll", Stage3SetupSupport.nekoNdllHostPlatform()]);
					mkdirp(src);
					mkdirp(ndll);
					final paths = Stage3SetupSupport.collectNekoNdllPaths([
						{
							classPaths: ["dummy_ndll/src"],
							defines: [],
							macros: [],
							unknownArgs: ["-L dummy_ndll/ndll"]
						}
					], tmp);
					if (paths.length != 1)
						throw "expected one Neko ndll path, got " + paths.length;
					Sys.println("ndll-path=" + paths[0]);
				case "collect-neko-ndll-direct-platform":
					final libRoot = Path.join([tmp, "dummy_ndll"]);
					final ndll = Path.join([libRoot, "ndll", Stage3SetupSupport.nekoNdllHostPlatform()]);
					mkdirp(ndll);
					final paths = Stage3SetupSupport.collectNekoNdllPaths([
						{
							classPaths: [],
							defines: [],
							macros: [],
							unknownArgs: ["-L dummy_ndll/ndll/" + Stage3SetupSupport.nekoNdllHostPlatform() + "/"]
						}
					], tmp);
					if (paths.length != 1)
						throw "expected one direct Neko ndll path, got " + paths.length;
					Sys.println("ndll-direct-path=" + paths[0]);
				case "library-resolver-haxelib-always":
					final libRoot = Path.join([tmp, "dummy_ndll"]);
					mkdirp(Path.join([libRoot, "ndll", Stage3SetupSupport.nekoNdllHostPlatform()]));
					final fakeLix = Path.join([absBin, "lix"]);
					File.saveContent(fakeLix, "#!/usr/bin/env sh\nexit 1\n");
					final fakeHaxelib = Path.join([absBin, "haxelib"]);
					File.saveContent(fakeHaxelib,
						"#!/usr/bin/env sh\nif [ \"$1\" = \"path\" ]; then printf '%s\\n' '-lib dummy_ndll is missing haxe_libraries/dummy_ndll.hxml'; exit 0; fi\nif [ \"$1\" = \"--always\" ] && [ \"$2\" = \"path\" ]; then printf '%s\\n' '-L dummy_ndll/ndll/' 'dummy_ndll/' '-D dummy_ndll=0.0.0'; exit 0; fi\nexit 1\n");
					if (Sys.command("chmod", ["+x", fakeLix]) != 0 || Sys.command("chmod", ["+x", fakeHaxelib]) != 0)
						throw "failed to chmod fake haxelib/lix";
					Sys.putEnv("LIX_BIN", fakeLix);
					Sys.putEnv("HAXELIB_BIN", fakeHaxelib);
					final spec = LibraryResolver.resolve("dummy_ndll", tmp, new Map<String, Bool>(), 0);
					if (spec.classPaths.length != 1 || spec.classPaths[0] != "dummy_ndll/")
						throw "expected haxelib --always classpath fallback, got " + spec.classPaths.join(",");
					if (spec.unknownArgs.indexOf("-L dummy_ndll/ndll/") == -1)
						throw "expected haxelib --always native -L path";
					Sys.println("resolver=always");
				case "library-resolver-lix-scoped-miss":
					final libRoot = Path.join([tmp, "dummy_ndll"]);
					mkdirp(Path.join([libRoot, "ndll", Stage3SetupSupport.nekoNdllHostPlatform()]));
					final fakeLix = Path.join([absBin, "lix"]);
					File.saveContent(fakeLix,
						"#!/usr/bin/env sh\nif [ \"$1\" = \"run-haxelib\" ] && [ \"$2\" = \"path\" ]; then printf '%s\\n' '-lib dummy_ndll is missing haxe_libraries/dummy_ndll.hxml'; exit 0; fi\nexit 1\n");
					final fakeHaxelib = Path.join([absBin, "haxelib"]);
					File.saveContent(fakeHaxelib,
						"#!/usr/bin/env sh\nif [ \"$1\" = \"path\" ]; then exit 1; fi\nif [ \"$1\" = \"--always\" ] && [ \"$2\" = \"path\" ]; then printf '%s\\n' '-L dummy_ndll/ndll/' 'dummy_ndll/' '-D dummy_ndll=0.0.0'; exit 0; fi\nexit 1\n");
					if (Sys.command("chmod", ["+x", fakeLix]) != 0 || Sys.command("chmod", ["+x", fakeHaxelib]) != 0)
						throw "failed to chmod fake haxelib/lix";
					Sys.putEnv("LIX_BIN", fakeLix);
					Sys.putEnv("HAXELIB_BIN", fakeHaxelib);
					final spec = LibraryResolver.resolve("dummy_ndll", tmp, new Map<String, Bool>(), 0);
					if (spec.classPaths.length != 1 || spec.classPaths[0] != "dummy_ndll/")
						throw "expected haxelib --always classpath fallback after Lix miss, got " + spec.classPaths.join(",");
					if (spec.unknownArgs.indexOf("-L dummy_ndll/ndll/") == -1)
						throw "expected haxelib --always native -L path after Lix miss";
					Sys.println("resolver=lix-scoped-miss");
				case "library-resolver-lix-empty":
					final libRoot = Path.join([tmp, "dummy_ndll"]);
					mkdirp(Path.join([libRoot, "ndll", Stage3SetupSupport.nekoNdllHostPlatform()]));
					final fakeLix = Path.join([absBin, "lix"]);
					File.saveContent(fakeLix, "#!/usr/bin/env sh\nif [ \"$1\" = \"run-haxelib\" ] && [ \"$2\" = \"path\" ]; then exit 0; fi\nexit 1\n");
					final fakeHaxelib = Path.join([absBin, "haxelib"]);
					File.saveContent(fakeHaxelib,
						"#!/usr/bin/env sh\nif [ \"$1\" = \"path\" ]; then exit 1; fi\nif [ \"$1\" = \"--always\" ] && [ \"$2\" = \"path\" ]; then printf '%s\\n' '-L dummy_ndll/ndll/' 'dummy_ndll/' '-D dummy_ndll=0.0.0'; exit 0; fi\nexit 1\n");
					if (Sys.command("chmod", ["+x", fakeLix]) != 0 || Sys.command("chmod", ["+x", fakeHaxelib]) != 0)
						throw "failed to chmod fake haxelib/lix";
					Sys.putEnv("LIX_BIN", fakeLix);
					Sys.putEnv("HAXELIB_BIN", fakeHaxelib);
					final spec = LibraryResolver.resolve("dummy_ndll", tmp, new Map<String, Bool>(), 0);
					if (spec.classPaths.length != 1 || spec.classPaths[0] != "dummy_ndll/")
						throw "expected haxelib --always classpath fallback after empty Lix result, got " + spec.classPaths.join(",");
					if (spec.unknownArgs.indexOf("-L dummy_ndll/ndll/") == -1)
						throw "expected haxelib --always native -L path after empty Lix result";
					Sys.println("resolver=lix-empty");
				case _:
					throw "unknown mode: " + mode;
			}
		} catch (e:haxe.Exception) {
			Sys.putEnv("PATH", oldPath == null ? "" : oldPath);
			Sys.putEnv("NEKOPATH", oldNekoPath == null ? "" : oldNekoPath);
			Sys.putEnv("HXHX_FAKE_NEKO_PRINT_PATH", oldFakeNekoPrintPath == null ? "" : oldFakeNekoPrintPath);
			Sys.putEnv("HAXELIB_BIN", oldHaxelibBin == null ? "" : oldHaxelibBin);
			Sys.putEnv("LIX_BIN", oldLixBin == null ? "" : oldLixBin);
			rmrf(tmp);
			throw e.message;
		} catch (raw:String) {
			Sys.putEnv("PATH", oldPath == null ? "" : oldPath);
			Sys.putEnv("NEKOPATH", oldNekoPath == null ? "" : oldNekoPath);
			Sys.putEnv("HXHX_FAKE_NEKO_PRINT_PATH", oldFakeNekoPrintPath == null ? "" : oldFakeNekoPrintPath);
			Sys.putEnv("HAXELIB_BIN", oldHaxelibBin == null ? "" : oldHaxelibBin);
			Sys.putEnv("LIX_BIN", oldLixBin == null ? "" : oldLixBin);
			rmrf(tmp);
			throw raw;
		}
		Sys.putEnv("PATH", oldPath == null ? "" : oldPath);
		Sys.putEnv("NEKOPATH", oldNekoPath == null ? "" : oldNekoPath);
		Sys.putEnv("HXHX_FAKE_NEKO_PRINT_PATH", oldFakeNekoPrintPath == null ? "" : oldFakeNekoPrintPath);
		Sys.putEnv("HAXELIB_BIN", oldHaxelibBin == null ? "" : oldHaxelibBin);
		Sys.putEnv("LIX_BIN", oldLixBin == null ? "" : oldLixBin);
		rmrf(tmp);
	}
}
