package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)

import haxe.io.Path;

import reflaxe.output.OutputManager;

class RuntimeCopier {
	static inline final HXHX_RUNTIME_PREFIX = "HxHx";

	static function tryResolveStdDir():Null<String> {
		#if macro
		try {
			// `std/` is on the classpath via haxe_libraries/reflaxe.ocaml.hxml.
			// Resolve a known file inside it so we can locate `std/runtime/`.
			final ocamlList = haxe.macro.Context.resolvePath("ocaml/List.hx");
			final ocamlDir = Path.directory(ocamlList); // .../std/ocaml
			return Path.directory(ocamlDir); // .../std
		} catch (_:Dynamic) {
			return null;
		}
		#else
		return null;
		#end
	}

	public static function copy(output:OutputManager, destSubdir:String = "runtime"):Void {
		final stdDir = tryResolveStdDir();
		if (stdDir == null) return;

		final runtimeDir = Path.join([stdDir, "runtime"]);
		if (!sys.FileSystem.exists(runtimeDir) || !sys.FileSystem.isDirectory(runtimeDir)) return;

		#if macro
		final allowHxHxRuntime = haxe.macro.Context.defined("hih_native_parser")
			|| haxe.macro.Context.defined("hxhx_native_frontend")
			|| haxe.macro.Context.defined("hxhx");
		#else
		final allowHxHxRuntime = false;
		#end

		for (name in sys.FileSystem.readDirectory(runtimeDir)) {
			if (!StringTools.endsWith(name, ".ml") && !StringTools.endsWith(name, ".mli")) continue;
			if (!allowHxHxRuntime && StringTools.startsWith(name, HXHX_RUNTIME_PREFIX)) continue;
			final src = Path.join([runtimeDir, name]);
			if (!sys.FileSystem.exists(src) || sys.FileSystem.isDirectory(src)) continue;
			final rel = destSubdir + "/" + name;
			final content = sys.io.File.getContent(src);
			output.saveFile(rel, content);
		}
	}
}

#end
