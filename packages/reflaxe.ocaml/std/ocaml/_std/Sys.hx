/**
	OCaml target override for `Sys`.

	This keeps the *Haxe* `Sys` API stable and portable while allowing direct
	operations to name checked `HxSys` boundaries in their typed declarations.

	Stream access names the generated Haxe `sys.io.Stdio` implementation directly.
	Methods needing nullable branching implement that choice in Haxe, then call
	narrow checked `HxSys` operations. Dynamic output now follows the same facade:
	the compiler seals the `Dynamic` carrier before this inline method calls the
	runtime boundary, so the target builder does not need a `Sys.print` method-name
	special case.
**/
@:require(sys)
extern class Sys {
	/**
		Prints any value to the standard output.
	**/
	static inline function print(v:Dynamic):Void {
		final value:Dynamic = v;
		NativeHxSys.printValue(value);
	}

	/**
		Prints any value to the standard output, followed by a newline.
	**/
	static inline function println(v:Dynamic):Void {
		final value:Dynamic = v;
		NativeHxSys.printlnValue(value);
	}

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
	static inline function putEnv(s:String, v:Null<String>):Void {
		if (v == null)
			NativeHxSys.removeEnv(s);
		else
			NativeHxSys.putEnvValue(s, v);
	}

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

		The OCaml backend does not currently provide a checked locale-changing
		primitive, so this reports that the requested locale was not applied.
	**/
	static inline function setTimeLocale(loc:String):Bool {
		return false;
	}

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
	static inline function command(cmd:String, ?args:Array<String>):Int {
		return args == null ? NativeHxSys.commandShell(cmd) : NativeHxSys.commandArgs(cmd, args);
	}

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
	@:native("Sys_io_Stdio.stdin") static function stdin():haxe.io.Input;

	/**
		Returns the standard output of the process.
	**/
	@:native("Sys_io_Stdio.stdout") static function stdout():haxe.io.Output;

	/**
		Returns the standard error of the process.
	**/
	@:native("Sys_io_Stdio.stderr") static function stderr():haxe.io.Output;
}

/**
	Checked OCaml operations used only after the public Haxe `Sys` facade has
	selected the required nullable/optional branch.
**/
@:ocamlRuntime("haxe-system")
@:native("HxSys")
private extern class NativeHxSys {
	static function printValue(value:Dynamic):Void;
	static function printlnValue(value:Dynamic):Void;
	static function putEnvValue(name:String, value:String):Void;
	static function removeEnv(name:String):Void;
	static function commandShell(command:String):Int;
	static function commandArgs(command:String, arguments:Array<String>):Int;
}
