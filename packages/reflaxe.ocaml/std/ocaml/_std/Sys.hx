/**
	OCaml target override for `Sys`.

	This keeps the *Haxe* `Sys` API stable and portable while allowing direct
	operations to name checked `HxSys` boundaries in their typed declarations.

	Methods that still need Haxe-to-OCaml argument conversion or stream routing
	remain explicit compiler-owned cases until a typed Haxe facade can preserve
	their behavior.
**/
@:require(sys)
extern class Sys {
	/**
		Prints any value to the standard output.
	**/
	static function print(v:Dynamic):Void;

	/**
		Prints any value to the standard output, followed by a newline.
	**/
	static function println(v:Dynamic):Void;

	/**
		Returns all the arguments that were passed in the command line.
	**/
	@:ocamlRuntime("haxe-system")
	@:native("HxSys.args")
	static function args():Array<String>;

	/**
		Returns the value of the given environment variable, or `null` if it
		doesn't exist.
	**/
	@:ocamlRuntime("haxe-system")
	@:native("HxSys.getEnv")
	static function getEnv(s:String):String;

	/**
		Sets the value of the given environment variable.
		If `v` is `null`, the environment variable is removed.
	**/
	static function putEnv(s:String, v:Null<String>):Void;

	/**
		Returns a map of the current environment variables and their values.
	**/
	@:ocamlRuntime("haxe-system")
	@:native("HxSys.environment")
	static function environment():Map<String, String>;

	/**
		Suspends execution for the given length of time (in seconds).
	**/
	@:ocamlRuntime("haxe-system")
	@:native("HxSys.sleep")
	static function sleep(seconds:Float):Void;

	/**
		Changes the current time locale.
	**/
	static function setTimeLocale(loc:String):Bool;

	/**
		Gets the current working directory.
	**/
	@:ocamlRuntime("haxe-system")
	@:native("HxSys.getCwd")
	static function getCwd():String;

	/**
		Changes the current working directory.
	**/
	@:ocamlRuntime("haxe-system")
	@:native("HxSys.setCwd")
	static function setCwd(s:String):Void;

	/**
		Returns the type of the current system.
	**/
	@:ocamlRuntime("haxe-system")
	@:native("HxSys.systemName")
	static function systemName():String;

	/**
		Runs the given command.
	**/
	static function command(cmd:String, ?args:Array<String>):Int;

	/**
		Exits the current process with the given exit code.
	**/
	@:ocamlRuntime("haxe-system")
	@:native("HxSys.exit")
	static function exit(code:Int):Void;

	/**
		Gives the most precise timestamp value available (in seconds).
	**/
	@:ocamlRuntime("haxe-system")
	@:native("HxSys.time")
	static function time():Float;

	/**
		Gives the most precise CPU timestamp value available (in seconds).
	**/
	@:ocamlRuntime("haxe-system")
	@:native("HxSys.cpuTime")
	static function cpuTime():Float;

	@:ocamlRuntime("haxe-system")
	@:native("HxSys.programPath")
	@:deprecated("Use programPath instead") static function executablePath():String;

	/**
		Returns the absolute path to the current program file that we are running.
	**/
	@:ocamlRuntime("haxe-system")
	@:native("HxSys.programPath")
	static function programPath():String;

	/**
		Reads a single input character from the standard input and returns it.
	**/
	@:ocamlRuntime("haxe-system")
	@:native("HxSys.getChar")
	static function getChar(echo:Bool):Int;

	/**
		Returns the standard input of the process.
	**/
	static function stdin():haxe.io.Input;

	/**
		Returns the standard output of the process.
	**/
	static function stdout():haxe.io.Output;

	/**
		Returns the standard error of the process.
	**/
	static function stderr():haxe.io.Output;
}
