/**
	Stats from a `ProjectCompiler.compileProject` run.

	Why:
	- This is a class (not a typedef) so we don’t depend on structural typing
	  support in the OCaml target yet.
**/
class CompileStats {
	public var files:Int;
	public var parsed:Int;
	public var cached:Int;
	public var mtimePositive:Bool;

	public function new() {
		files = 0;
		parsed = 0;
		cached = 0;
		mtimePositive = true;
	}
}
