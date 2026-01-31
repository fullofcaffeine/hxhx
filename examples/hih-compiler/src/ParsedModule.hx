/**
	A placeholder “parsed module”.

	Why:
	- We intentionally avoid structural typing (`typedef { ... }`) for now, so the
	  OCaml target doesn’t need full anonymous-structure support to run this
	  acceptance example.
**/
class ParsedModule {
	final source:String;

	public function new(source:String) {
		this.source = source;
	}

	public function getSource():String {
		return source;
	}
}

