/**
	Typed function environment skeleton.

	Why:
	- Functions are the first place where typing becomes “real”:
	  arguments, return types, locals, and `return` semantics.
	- This environment is the future home of local symbol tables and inferred
	  types, but Stage 3 starts with signatures.

	What:
	- Function name.
	- Parameter symbols (name + type-hint-derived `TyType`).
	- Return type (type-hint-derived `TyType`).
**/
class TyFunctionEnv {
	final name:String;
	final params:Array<TySymbol>;
	final returnType:TyType;

	public function new(name:String, params:Array<TySymbol>, returnType:TyType) {
		this.name = name;
		this.params = params;
		this.returnType = returnType;
	}

	public function getName():String return name;
	public function getParams():Array<TySymbol> return params;
	public function getReturnType():TyType return returnType;
}

