/**
	Stage 2 typer skeleton.

	Why:
	- The “typer” is the heart of the compiler and the largest bootstrapping
	  milestone.
	- Even as a stub, we keep the API shaped like the real thing: consume a parsed
	  module and return a typed module.
**/
class TyperStage {
	public static function typeModule(m:ParsedModule):TypedModule {
		return new TypedModule(m);
	}
}
