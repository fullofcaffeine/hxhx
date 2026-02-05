/**
	A placeholder “parsed module”.

	Why:
	- We intentionally avoid structural typing (typedef {...}) for now, so the
	  OCaml target doesn’t need full anonymous-structure support to run this
	  acceptance example.
**/
class ParsedModule {
	final source:String;
	final filePath:String;
	final decl:HxModuleDecl;

	public function new(source:String, decl:HxModuleDecl, filePath:String) {
		this.source = source;
		this.decl = decl;
		this.filePath = filePath;
	}

	public function getSource():String {
		return source;
	}

	/**
		Best-effort source file path used for diagnostics.

		Why
		- Stage 3 typer errors must report `file:line:col` to be actionable and
		  to match the ergonomics of the upstream Haxe compiler.
		- Some bootstrap seams (e.g. parsing from raw strings) have no real file;
		  we still want a stable placeholder rather than `null`.
	**/
	public function getFilePath():String {
		return filePath;
	}

	public function getDecl():HxModuleDecl {
		return decl;
	}
}
