package haxe.macro;

#if macro
import haxe.macro.Context;
#else
import hxhxmacrohost.api.Compiler as HostCompiler;
import hxhxmacrohost.api.Context as HostContext;
import haxe.io.Path;
import StringTools;
#end

/**
	Macro-host override for `haxe.macro.Compiler` (Stage 4 bring-up).

	Why
	- The macro host is compiled with `-lib reflaxe.ocaml`, which runs real compiler configuration macros
	  (e.g. `nullSafety(...)`, Reflaxe initialization).
	- Separately, runtime macro modules compiled into the macro host may import `haxe.macro.Compiler` to
	  affect compilation (defines, classpaths, generated modules).

	What
	- `#if macro`: forward a small subset to the compiler's macro API via `Context.load`.
	- `#else`: map a small runtime subset to the Stage4 reverse-RPC API (`hxhxmacrohost.api.Compiler`).

	Gotchas
	- Keep the runtime subset small and grow it only with tests.
**/
enum NullSafetyMode {
	Loose;
	Strict;
	StrictThreaded;
}

typedef MetadataDescription = {
	final metadata:String;
	final doc:String;
	@:optional final links:Array<String>;
	@:optional final params:Array<String>;
	@:optional final platforms:Array<haxe.display.Display.Platform>;
	@:optional final targets:Array<haxe.display.Display.MetadataTarget>;
}

typedef DefineDescription = {
	final define:String;
	final doc:String;
	@:optional final links:Array<String>;
	@:optional final params:Array<String>;
	@:optional final platforms:Array<haxe.display.Display.Platform>;
}

typedef CompilerConfiguration = {
	final version:Int;
	final args:Array<String>;
	@:optional final debug:Bool;
	@:optional final verbose:Bool;
	@:optional final foptimize:Bool;
	@:optional final platform:Dynamic;
	final platformConfig:haxe.macro.PlatformConfig;
	final stdPath:Array<String>;
}

#if macro
class Compiler {
	macro static public function getDefine(key:String) {
		return macro $v{haxe.macro.Context.definedValue(key)};
	}

	public static function define(flag:String, ?value:String):Void {
		load("define", 2)(flag, value);
	}

	public static function addClassPath(path:String):Void {
		load("add_class_path", 1)(path);
	}

	public static function include(pack:String, ?rec:Bool = true, ?ignoredModules:Array<String>, ?classPaths:Array<String>, strict:Bool = false):Void {
		load("include", 5)(pack, rec, ignoredModules, classPaths, strict);
	}

	public static function getConfiguration():CompilerConfiguration {
		return load("get_configuration", 0)();
	}

	public static function addGlobalMetadata(pathFilter:String, meta:String, ?recursive:Bool = true, ?toTypes:Bool = true, ?toFields:Bool = false):Void {
		load("add_global_metadata_impl", 5)(pathFilter, meta, recursive, toTypes, toFields);
	}

	public static function nullSafety(path:String, mode:NullSafetyMode = Loose, recursive:Bool = true):Void {
		addGlobalMetadata(path, '@:nullSafety($mode)', recursive);
	}

	public static function registerCustomMetadata(meta:MetadataDescription, ?source:String):Void {
		load("register_metadata_impl", 2)(meta, source);
	}

	static inline function load(f:String, nargs:Int):Dynamic {
		return @:privateAccess haxe.macro.Context.load(f, nargs);
	}
}
#else
class Compiler {
	static function normalizedModulePath(path:String):String {
		return path == null ? "" : StringTools.trim(StringTools.replace(path, "/", "."));
	}

	static function effectiveClassPaths(classPaths:Array<String>):Array<String> {
		final out = new Array<String>();
		final source = classPaths != null && classPaths.length > 0 ? classPaths : HostContext.getClassPath();
		if (source == null)
			return out;
		for (cp in source) {
			if (cp == null)
				continue;
			final trimmed = StringTools.trim(cp);
			if (trimmed.length == 0 || out.indexOf(trimmed) != -1)
				continue;
			out.push(trimmed);
		}
		return out;
	}

	static function shouldIgnoreModule(modulePath:String, ignoredModules:Array<String>):Bool {
		if (ignoredModules == null || ignoredModules.length == 0)
			return false;
		final normalized = normalizedModulePath(modulePath);
		for (entry in ignoredModules) {
			if (normalizedModulePath(entry) == normalized)
				return true;
		}
		return false;
	}

	static function collectRecursiveModules(rootDir:String, packageParts:Array<String>, out:Array<String>, seen:Array<String>,
			ignoredModules:Array<String>):Void {
		if (!sys.FileSystem.exists(rootDir) || !sys.FileSystem.isDirectory(rootDir))
			return;
		for (entry in sys.FileSystem.readDirectory(rootDir)) {
			if (entry == null || entry.length == 0)
				continue;
			final full = Path.join([rootDir, entry]);
			if (sys.FileSystem.isDirectory(full)) {
				collectRecursiveModules(full, packageParts.concat([entry]), out, seen, ignoredModules);
				continue;
			}
			if (!StringTools.endsWith(entry, ".hx"))
				continue;
			final moduleName = entry.substr(0, entry.length - 3);
			final modulePath = packageParts.concat([moduleName]).join(".");
			if (modulePath.length == 0 || shouldIgnoreModule(modulePath, ignoredModules) || seen.indexOf(modulePath) != -1)
				continue;
			seen.push(modulePath);
			out.push(modulePath);
		}
	}

	public static function define(flag:String, ?value:String):Void {
		HostCompiler.define(flag, value == null ? "" : value);
	}

	public static function getDefine(key:String):Null<String> {
		return HostCompiler.getDefine(key);
	}

	public static function getConfiguration():CompilerConfiguration {
		return HostCompiler.getConfiguration();
	}

	public static function addClassPath(path:String):Void {
		HostCompiler.addClassPath(path);
	}

	public static function emitOcamlModule(name:String, source:String):Void {
		HostCompiler.emitOcamlModule(name, source);
	}

	public static function emitHxModule(name:String, source:String):Void {
		HostCompiler.emitHxModule(name, source);
	}

	/**
		Runtime bring-up `Compiler.include(...)`.

		Why
		- Real initialization macros often use `Compiler.include(...)` instead of custom helper entrypoints.
		- The compiler side already has an exact-module inclusion rung; exposing it here lets runtime
		  macro code reach that effect through the normal `haxe.macro.Compiler` surface.

		What
		- Supports the conservative runtime subset that already matters for target helpers:
		  - exact-module include
		  - recursive package walking from compiler-visible classpaths
		  - exact-module ignore rules
		  - optional explicit classpaths
		  - `strict=true` meaning "fail if nothing matched"

		Gotchas
		- Still intentionally narrower than upstream:
		  - ignore rules are exact module-path matches only
		  - no richer package filters or typed reachability semantics
	**/
	public static function include(pack:String, ?rec:Bool = true, ?ignoredModules:Array<String>, ?classPaths:Array<String>, strict:Bool = false):Void {
		if (pack == null || pack.length == 0)
			return;
		final normalizedPack = normalizedModulePath(pack);
		if (normalizedPack.length == 0)
			return;

		final included = new Array<String>();
		final seen = new Array<String>();
		if (!shouldIgnoreModule(normalizedPack, ignoredModules)) {
			included.push(normalizedPack);
			seen.push(normalizedPack);
		}

		if (rec != false) {
			final cps = effectiveClassPaths(classPaths);
			final parts = normalizedPack.split(".");
			for (cp in cps) {
				final packageDir = Path.join([cp].concat(parts));
				collectRecursiveModules(packageDir, parts, included, seen, ignoredModules);
			}
		}

		if (included.length == 0) {
			if (strict)
				throw "runtime Compiler.include: no modules matched " + normalizedPack;
			return;
		}

		for (modulePath in included)
			HostCompiler.includeModule(modulePath);
	}
}
#end
