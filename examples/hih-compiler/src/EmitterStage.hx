/**
	Stage 2 codegen/emitter skeleton.

	Why:
	- The real Haxe compiler has multiple generators; for Haxe-in-Haxe we’ll need
	  at minimum a bytecode or OCaml-emission strategy for self-hosting.
	- This stage is a stub that records the intended boundary.
**/
class EmitterStage {
	public function new() {}

	public function emit(_:MacroExpandedModule):Void {
		// Stub: eventually write output files / bytecode.
	}
}

