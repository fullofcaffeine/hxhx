/**
	Typed function environment skeleton.

	Why:
	- Functions are the first place where typing becomes “real”:
	  arguments, return types, locals, and `return` semantics.
	- This environment is the future home of local symbol tables and inferred
	  types, but Stage 3 starts with signatures + a minimal local scope.

	What:
	- Function name.
	- Parameter symbols (name + type-hint-derived `TyType`).
	- Local symbols (Stage 3: empty unless the parser supports `var`).
	- Return type (from hint or inferred from `return`).
	- Return-expression type (best-effort; used for debugging bootstrap typing).
**/
class TyFunctionEnv {
	final name:String;
	final params:Array<TySymbol>;
	final locals:Array<TySymbol>;
	final returnType:TyType;
	final returnExprType:TyType;

	public function new(name:String, params:Array<TySymbol>, locals:Array<TySymbol>, returnType:TyType, returnExprType:TyType) {
		this.name = name;
		this.params = params;
		this.locals = locals;
		this.returnType = returnType;
		this.returnExprType = returnExprType;
	}

	public function getName():String
		return name;

	public function getParams():Array<TySymbol>
		return params;

	public function getLocals():Array<TySymbol>
		return locals;

	public function getReturnType():TyType
		return returnType;

	public function getReturnExprType():TyType
		return returnExprType;

	/**
		Declare a new local symbol.

		Why
		- Stage 3 introduces `var` statements into the parser, which means the
		  typer must build a local scope before it can type identifier usage
		  inside the function body.

		How
		- We keep declaration order deterministic: locals are appended in source
		  order and lookups prefer parameters over locals.
	**/
	public function declareLocal(name:String, ty:TyType):TySymbol {
		final sym = new TySymbol(name, ty);
		locals.push(sym);
		return sym;
	}

	/**
		Resolve a symbol (parameter or local) by name.
	**/
	public function resolveSymbol(name:String):Null<TySymbol> {
		for (p in params)
			if (p.getName() == name)
				return p;
		for (l in locals)
			if (l.getName() == name)
				return l;
		return null;
	}

	/**
		Resolve a symbol in this function's local scope.

		Why:
		- Even at Stage 3, we want identifier typing to be “real” so that basic
		  fixtures (like `return arg;`) produce meaningful types.

		What:
		- Looks up parameters first, then locals.

		How:
		- We intentionally use a small linear search: scopes are tiny in the
		  bootstrap fixture set, and determinism matters more than asymptotics.
	**/
	public function resolveLocal(name:String):TyType {
		final sym = resolveSymbol(name);
		return sym == null ? TyType.unknown() : sym.getType();
	}
}
