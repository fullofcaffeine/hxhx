/**
	Deterministic “upstream-shaped” parser fixtures for Stage 2.

	Why:
	- We want the Stage 2 compiler to gradually converge on the upstream Haxe
	  frontend behavior.
	- Upstream `tests/misc` contains many small, focused fixtures (module
	  resolution, metadata placement, multiple types per file, etc.).
	- However, we do not want `workloads/hih-compiler` to depend on a local
	  checkout of the upstream repo at runtime (CI determinism).

	What:
	- This class stores:
	  - a human label pointing at the upstream fixture we are emulating
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
