/**
	Typed class environment skeleton.

	Why:
	- Stage 3 needs a stable representation for the typed “surface” of a class:
	  fields, methods, statics, and (later) type parameters.
	- For now, we only track function signatures.
**/
class TyClassEnv {
	final name:String;
	final functions:Array<TyFunctionEnv>;

	public function new(name:String, functions:Array<TyFunctionEnv>) {
		this.name = name;
		this.functions = functions;
	}

	public function getName():String
		return name;

	public function getFunctions():Array<TyFunctionEnv>
		return functions;
}
