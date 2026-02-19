/**
	Function argument AST node for the `hih-compiler` subset.

	Why:
	- Stage 3 typing needs a stable shape for parameters so we can populate the
	  local environment and check calls.

	What:
	- Name.
	- Optional type hint text (not yet parsed into a full type tree).
	- Optional default value expression (very small subset for now).

	How:
	- We intentionally store type hints as raw text initially to avoid blocking
	  on a full type grammar. The typer can interpret the subset it supports.
**/
class HxFunctionArg {
	public final name:String;
	public final typeHint:String;
	public final defaultValue:HxDefaultValue;
	public final isOptional:Bool;
	public final isRest:Bool;

	public function new(name:String, typeHint:String, defaultValue:HxDefaultValue, isOptional:Bool = false, isRest:Bool = false) {
		this.name = name;
		this.typeHint = typeHint;
		this.defaultValue = defaultValue;
		this.isOptional = isOptional;
		this.isRest = isRest;
	}

	/**
		Non-inline getters for cross-module use.

		See `HxModuleDecl.getPackagePath` for the `-opaque` rationale.
	**/
	public static function getName(a:HxFunctionArg):String
		return a.name;

	public static function getTypeHint(a:HxFunctionArg):String
		return a.typeHint;

	public static function getDefaultValue(a:HxFunctionArg):HxDefaultValue
		return a.defaultValue;

	public static function getIsOptional(a:HxFunctionArg):Bool
		return a.isOptional;

	public static function getIsRest(a:HxFunctionArg):Bool
		return a.isRest;
}
