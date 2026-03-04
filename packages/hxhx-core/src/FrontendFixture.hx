/**
	Deterministic parser fixtures for Stage 2 frontend checks.

	Why:
	- Stage 2 needs small, stable fixtures that exercise package/class/function
	  parsing behavior without relying on external repositories at runtime.
	- Fixtures are intentionally repo-owned to keep clean-room provenance clear.

	What:
	- This class stores:
	  - a human label for the local fixture case
	  - a source string (kept small and deterministic)
	  - the minimal expected AST summary for this phase (package + first class +
		whether a static `main` exists)

	How:
	- We avoid anonymous-structure typing in this example because the OCaml
	  target is still growing its representation for structural types.
**/
class FrontendFixture {
	public final label:String;
	public final source:String;
	public final expectPackagePath:String;
	public final expectMainClassName:String;
	public final expectHasStaticMain:Bool;

	public function new(label:String, source:String, expectPackagePath:String, expectMainClassName:String, expectHasStaticMain:Bool) {
		this.label = label;
		this.source = source;
		this.expectPackagePath = expectPackagePath;
		this.expectMainClassName = expectMainClassName;
		this.expectHasStaticMain = expectHasStaticMain;
	}

	public function getLabel():String {
		return label;
	}

	public function getSource():String {
		return source;
	}

	public function getExpectPackagePath():String {
		return expectPackagePath;
	}

	public function getExpectMainClassName():String {
		return expectMainClassName;
	}

	public function getExpectHasStaticMain():Bool {
		return expectHasStaticMain;
	}
}
