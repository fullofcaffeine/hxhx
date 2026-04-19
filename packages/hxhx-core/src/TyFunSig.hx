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
	final argNames:Array<String>;
	final args:Array<TyType>;
	final argOptional:Array<Bool>;
	final argRest:Array<Bool>;
	final returnType:TyType;
	final pos:HxPos;

	public function new(name:String, isStatic:Bool, argNames:Array<String>, args:Array<TyType>, argOptional:Array<Bool>, argRest:Array<Bool>,
			returnType:TyType, pos:HxPos) {
		this.name = name;
		this.isStatic = isStatic;
		this.argNames = argNames == null ? [] : argNames;
		this.args = args == null ? [] : args;
		this.argOptional = argOptional == null ? [] : argOptional;
		this.argRest = argRest == null ? [] : argRest;
		this.returnType = returnType == null ? TyType.unknown() : returnType;
		this.pos = pos == null ? HxPos.unknown() : pos;
	}

	public function getName():String
		return name;

	public function getIsStatic():Bool
		return isStatic;

	public function getArgNames():Array<String>
		return argNames;

	public function getArgs():Array<TyType>
		return args;

	public function getArgOptional():Array<Bool>
		return argOptional;

	public function getArgRest():Array<Bool>
		return argRest;

	public function getReturnType():TyType
		return returnType;

	public function getPos():HxPos
		return pos;

	public function acceptsArity(arity:Int):Bool {
		var required = 0;
		var hasRest = false;
		for (i in 0...args.length) {
			if (i < argRest.length && argRest[i]) {
				hasRest = true;
				continue;
			}
			if (!(i < argOptional.length && argOptional[i]))
				required++;
		}
		if (arity < required)
			return false;
		return hasRest || arity <= args.length;
	}
}
