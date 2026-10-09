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
	final typedProgramRevision:CompilerTypedProgramRevision;
	final selectedRuntimeFeatures:Array<String>;

	public final generatedOcamlModules:Array<MacroExpandedModule.GeneratedOcamlModule>;

	public function new(typedModules:Array<TypedModule>, macroMode:Bool, ?generatedOcamlModules:Array<MacroExpandedModule.GeneratedOcamlModule>,
			?selectedRuntimeFeatures:Array<String>) {
		this.typedModules = typedModules == null ? [] : typedModules.copy();
		this.typedProgramRevision = CompilerTypedProgramRevision.fromTypedModules(this.typedModules, macroMode);
		this.macroMode = macroMode;
		this.generatedOcamlModules = generatedOcamlModules == null ? [] : generatedOcamlModules.copy();
		this.selectedRuntimeFeatures = [];
		if (selectedRuntimeFeatures != null)
			for (name in selectedRuntimeFeatures) {
				if (name == null)
					throw "selected runtime feature requires a literal name";
				if (this.selectedRuntimeFeatures.indexOf(name) < 0)
					this.selectedRuntimeFeatures.push(name);
			}
		this.selectedRuntimeFeatures.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
	}

	/**
		Return feature-selection output for target-owned runtime setup. These literal
		protocol names are emission inputs, not additional target-neutral typing facts.
		Backends must not rediscover them from emitted or unused library bodies.
	 */
	public function getSelectedRuntimeFeatures():Array<String>
		return selectedRuntimeFeatures.copy();

	public function getTypedModules():Array<TypedModule> {
		return typedModules.copy();
	}

	/** Return the exact target-neutral revision sealed with this typed program. **/
	public function getTypedProgramRevision():CompilerTypedProgramRevision
		return typedProgramRevision;

	/** Ensure post-typing hooks have not changed parsed bodies behind this revision. **/
	public function assertTypedBodyRevisionsCurrent():Void {
		for (typedModule in typedModules)
			typedModule.assertBodyRevisionCurrent();
	}

	public function getGeneratedOcamlModules():Array<MacroExpandedModule.GeneratedOcamlModule> {
		return generatedOcamlModules.copy();
	}
}
