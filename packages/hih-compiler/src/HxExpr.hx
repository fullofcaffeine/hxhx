/**
	Expression AST for the `hih-compiler` bring-up.

	Why:
	- Stage 2 only needed a module “summary”. Stage 3 typing needs structured
	  expressions so we can infer types and produce a typed AST.
	- We keep this intentionally small and grow it rung-by-rung.

	What:
	- Supports a minimal subset needed by acceptance fixtures:
	  - constants (`null`, booleans, strings, ints, floats)
	  - identifier references
	  - field access (`a.b`)
	  - calls (`f(x, y)` and `a.b()`)

	How:
	- This is *not* the upstream Haxe AST. It is a bootstrap representation
	  designed to keep the example runnable in CI while we expand coverage.
**/
enum HxExpr {
	ENull;
	EBool(value:Bool);
	EString(value:String);
	EInt(value:Int);
	EFloat(value:Float);

	EIdent(name:String);
	EField(obj:HxExpr, field:String);
	ECall(callee:HxExpr, args:Array<HxExpr>);

	/**
		Best-effort placeholder for expressions we don't parse yet.

		We prefer to keep the parser permissive during early bootstrapping, while
		still allowing downstream stages to detect “unknown” shapes explicitly.
	**/
	EUnsupported(raw:String);
}

