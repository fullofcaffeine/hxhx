package haxe.macro;

#if macro
import haxe.macro.Context;
#else
import hxhxmacrohost.api.Compiler as HostCompiler;
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
		- Supports only the conservative bring-up subset:
		  - `pack` must be a single exact module path
		  - recursive package walking, ignore rules, alternative classpaths, and `strict` behavior
			are not modeled yet

		Gotchas
		- This is intentionally narrower than upstream package-recursive `Compiler.include(...)`.
		- Unsupported advanced arguments fail fast so later parity work stays explicit.
	**/
	public static function include(pack:String, ?rec:Bool = true, ?ignoredModules:Array<String>, ?classPaths:Array<String>, strict:Bool = false):Void {
		if (pack == null || pack.length == 0)
			return;
		// Optional runtime calls can arrive as `null` when callers omit the argument.
		// Treat that the same as the upstream default `true`; only an explicit `false`
		// is outside this bring-up rung today.
		if (rec == false)
			throw "runtime Compiler.include: rec=false is not implemented yet";
		if (ignoredModules != null && ignoredModules.length > 0)
			throw "runtime Compiler.include: ignore rules are not implemented yet";
		if (classPaths != null && classPaths.length > 0)
			throw "runtime Compiler.include: explicit classPaths are not implemented yet";
		if (strict == true)
			throw "runtime Compiler.include: strict mode is not implemented yet";
		HostCompiler.includeModule(pack);
	}
}
#end
