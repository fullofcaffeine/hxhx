/**
	A parsed “module” (source file) for this workload.

	Why:
	- We keep it small but shaped like a compiler pipeline input: a name and a
	  list of top-level declarations.
	- This is a class (not a typedef) to avoid depending on structural typing
	  support in the target at this stage.
**/
class Module {
	final name:String;
	final decls:Array<LetDecl>;

	public function new(name:String, decls:Array<LetDecl>) {
		this.name = name;
		this.decls = decls;
	}

	public function getName():String {
		return name;
	}

	public function getDecls():Array<LetDecl> {
		return decls;
	}
}
