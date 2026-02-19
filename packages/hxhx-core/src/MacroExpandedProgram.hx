/**
	Stage 2 "macro-expanded program" (multi-module placeholder).

	Why
	- Stage 3 has outgrown the single-module assumption:
	  - the resolver returns a module graph
	  - the typer can (best-effort) type multiple parsed modules
	  - the emitter wants to compile multiple OCaml compilation units
	- Keeping a distinct "program" container makes it easier to evolve the macro boundary
	  later (AST transforms, per-module hooks, incremental compilation, etc.).

	What
	- Holds:
	  - `typedModules`: the typed module graph (order is resolver/driver-defined)
	  - `generatedOcamlModules`: raw OCaml compilation units emitted by macros (Stage 4 bring-up)
	  - `macroMode`: placeholder flag for later "macros enabled" switching

	How
	- This is intentionally minimal: for now, macros do not transform the typed AST.
	  We only model "macros can generate extra OCaml files" as an artifact seam.
**/
class MacroExpandedProgram {
	public final macroMode:Bool;

	final typedModules:Array<TypedModule>;

	public final generatedOcamlModules:Array<MacroExpandedModule.GeneratedOcamlModule>;

	public function new(typedModules:Array<TypedModule>, macroMode:Bool, ?generatedOcamlModules:Array<MacroExpandedModule.GeneratedOcamlModule>) {
		this.typedModules = typedModules == null ? [] : typedModules;
		this.macroMode = macroMode;
		this.generatedOcamlModules = generatedOcamlModules == null ? [] : generatedOcamlModules;
	}

	public function getTypedModules():Array<TypedModule> {
		return typedModules;
	}

	public function getGeneratedOcamlModules():Array<MacroExpandedModule.GeneratedOcamlModule> {
		return generatedOcamlModules;
	}
}
