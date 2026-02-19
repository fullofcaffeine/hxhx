/**
	Function signature metadata used by the Stage 3 bootstrap typer.

	Why
	- Cross-module typing (Gate 1) needs a way to answer:
	  - “what is the return type of `Util.ping()`?”
	  - “is `this.x` a field, and what is its declared type?”
	- We cannot build the full upstream type system in one step, so we start by
	  indexing the declared surface of modules (fields + method signatures).

	What
	- A name, `static` flag, argument types, and return type.

	How
	- Types are `TyType` and are mostly derived from type hints at this stage.
	  The full typer will eventually infer/monomorphize these.
**/
class TyFunSig {
	final name:String;
	final isStatic:Bool;
	final args:Array<TyType>;
	final returnType:TyType;

	public function new(name:String, isStatic:Bool, args:Array<TyType>, returnType:TyType) {
		this.name = name;
		this.isStatic = isStatic;
		this.args = args == null ? [] : args;
		this.returnType = returnType == null ? TyType.unknown() : returnType;
	}

	public function getName():String
		return name;

	public function getIsStatic():Bool
		return isStatic;

	public function getArgs():Array<TyType>
		return args;

	public function getReturnType():TyType
		return returnType;
}
