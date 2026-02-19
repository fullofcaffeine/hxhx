/**
	A placeholder “macro-expanded module”.

	Why:
	- Supporting Haxe macros is a hard requirement for a production-grade
	  Haxe-in-Haxe compiler, but it will take multiple milestones.
	- We model the stage boundary now so we can evolve it without rewriting the
	  orchestration layer.
**/
class MacroExpandedModule {
	public final macroMode:Bool;
	final typed:TypedModule;
	public final generatedOcamlModules:Array<GeneratedOcamlModule>;

	public function new(typed:TypedModule, macroMode:Bool, ?generatedOcamlModules:Array<GeneratedOcamlModule>) {
		this.typed = typed;
		this.macroMode = macroMode;
		this.generatedOcamlModules = generatedOcamlModules == null ? [] : generatedOcamlModules;
	}

	public function getTyped():TypedModule {
		return typed;
	}

	public function getGeneratedOcamlModules():Array<GeneratedOcamlModule> {
		return generatedOcamlModules;
	}
}

/**
	An OCaml compilation unit emitted by a macro (Stage 4 bring-up).

	This models the *artifact* side of “macros generate code”, without attempting to represent
	typed Haxe AST transforms yet.
**/
typedef GeneratedOcamlModule = {
	final name:String;
	final source:String;
}
