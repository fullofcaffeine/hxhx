package reflaxe.ocaml.tooling;

/**
	Read-only environment boundary used by the doctor.

	Keeping command and filesystem access behind this interface makes failure
	policy deterministic in tests and prevents the doctor from becoming an
	installer or mutating a user's project while it diagnoses the environment.
**/
interface DoctorProbe {
	public function run(command:String, args:Array<String>):CommandResult;
	public function findExecutable(command:String):Null<String>;
	public function exists(path:String):Bool;
	public function isDirectory(path:String):Bool;
	public function readDirectory(path:String):Array<String>;
	public function readFile(path:String):Null<String>;
	public function absolutePath(path:String):String;
	public function systemName():String;
	public function environment(name:String):Null<String>;
}
