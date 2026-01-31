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

	public function new(typed:TypedModule, macroMode:Bool) {
		this.typed = typed;
		this.macroMode = macroMode;
	}

	public function getTyped():TypedModule {
		return typed;
	}
}

