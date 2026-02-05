/**
	A placeholder “parsed module”.

	Why:
	- We intentionally avoid structural typing (typedef {...}) for now, so the
	  OCaml target doesn’t need full anonymous-structure support to run this
	  acceptance example.
**/
class ParsedModule {
	final source:String;
	final decl:HxModuleDecl;

	public function new(source:String, decl:HxModuleDecl) {
		this.source = source;
		this.decl = decl;
	}

	public function getSource():String {
		return source;
	}

	public function getDecl():HxModuleDecl {
		return decl;
	}
}
