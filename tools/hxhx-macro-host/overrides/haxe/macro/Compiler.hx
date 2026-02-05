package haxe.macro;

#if (neko || eval)
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
	- `#if (neko || eval)`: forward a small subset to the compiler's macro API via `Context.load`.
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
	final stdPath:Array<String>;
}

#if (neko || eval)
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

	public static function addClassPath(path:String):Void {
		HostCompiler.addClassPath(path);
	}

	public static function emitOcamlModule(name:String, source:String):Void {
		HostCompiler.emitOcamlModule(name, source);
	}

	public static function emitHxModule(name:String, source:String):Void {
		HostCompiler.emitHxModule(name, source);
	}
}
#end
