/**
	Stage 2 macro-expansion skeleton.

	What:
	- In Haxe 4.3.7, macros can run compiler-time code, transform ASTs, and depend
	  on typing information.
	- This stage will eventually host the macro interpreter and the macro API
	  surface (`haxe.macro.*`).

	How (today):
	- Return the input unchanged in a placeholder container.
**/
class MacroStage {
	public function new() {}

	public function expand(m:TypedModule):MacroExpandedModule {
		return new MacroExpandedModule(m, true);
	}
}

