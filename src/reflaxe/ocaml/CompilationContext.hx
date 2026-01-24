package reflaxe.ocaml;

/**
 * Per-compilation, instance-based state for reflaxe.ocaml.
 *
 * M2+ will expand this to track mutability, renames, and other stateful decisions
 * required for correct OCaml emission (especially around closures).
 */
class CompilationContext {
	/** Tracks renames applied to Haxe locals to avoid collisions and keep output stable. */
	public final variableRenameMap:Map<String, String> = [];

	/** Tracks variables that are assigned after initialization (mutability inference hook). */
	public final assignedVars:Map<String, Bool> = [];

	/** Current module id (as seen by Reflaxe/Haxe), for debug and naming decisions. */
	public var currentModuleId:Null<String> = null;

	public function new() {}
}

