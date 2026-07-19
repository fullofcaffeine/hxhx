package reflaxe.ocaml.tooling;

/**
	Process, clock, console, and filesystem boundary for the authoring loop.

	The production host streams child output directly. Tests replace this boundary
	to prove polling and failure behavior without starting compilers or sleeping.
**/
interface AuthoringHost {
	public function run(command:String, args:Array<String>, workingDirectory:String):Int;
	public function exists(path:String):Bool;
	public function isDirectory(path:String):Bool;
	public function readDirectory(path:String):Array<String>;
	public function readFile(path:String):Null<String>;
	public function stat(path:String):Null<AuthoringFileStamp>;
	public function absolutePath(path:String):String;
	public function nowMilliseconds():Float;
	public function sleep(milliseconds:Int):Void;
	public function writeStdout(message:String):Void;
	public function writeStderr(message:String):Void;
}
