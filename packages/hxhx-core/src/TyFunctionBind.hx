/**
	`f.bind(...)` on a function value, as Haxe 4.3.7 types it (haxe_ocaml-kee1x).

	Why
	- Upstream's type_bind (src/typing/calls.ml:367-445) turns `f.bind(a, _)` into variables that
	  hold the callee and each bound argument, and a function over the missing parameters that
	  calls the callee with the arguments in order. genjs then prints those variables and that
	  closure. hxhx had no rule, so `f.bind(...)` typed as a field read on a function and its
	  result was unknown.

	What
	- A bound argument is evaluated once, at bind time; `_` leaves its parameter open; a trailing
	  parameter without an argument stays open unless it is optional, in which case it is omitted.
	- `rewrite` returns `{ final f0 = f; final a0 = a; (p1, ...) -> f0(a0, p1, ...); }`, the shape
	  genjs prints: the callee and the bound arguments are evaluated in order, once, before the
	  result exists. Every backend then sees ordinary locals and a closure. Null when the call is
	  not a bind of this shape.
	- Upstream converts a bound argument to its parameter type when the bind runs. A call through a
	  function value cannot run an abstract's `@:from` or `@:to` method yet
	  (TyCallbackArgumentContext), so a bound argument that needs one keeps the older path
	  (`needsConversion`, issues/Issue5783).
	- Payloads are compared in case bodies, never matched against String literals, because the
	  OCaml backend generator loses such bindings in the self-compile (haxe_ocaml-yuymr).
**/
final class TyFunctionBind {
	static inline final CALLEE = "__hxhx_bind_callee";
	static inline final BOUND = "__hxhx_bind_argument";
	static inline final OPEN = "__hxhx_bind_parameter";

	public static function rewrite(callee:HxExpr, arguments:Array<HxExpr>, calleeType:TyType, position:HxPos,
			needsConversion:(argument:HxExpr, parameter:TyType) -> Bool):Null<HxExpr> {
		if (calleeType == null || !calleeType.unwrapNull().isFunction())
			return null;
		// A function binding itself inside its own body has no result type yet (issues/Issue3280);
		// keep the ordinary call path there rather than publish an incomplete local.
		if (calleeType.unwrapNull().getFunctionReturn() == null || calleeType.unwrapNull().getFunctionReturn().hasUnknownComponent())
			return null;
		final parameters = calleeType.unwrapNull().getFunctionParameters();
		if (arguments.length > parameters.length)
			return null;
		final boundNames = new Array<String>();
		final boundValues = new Array<HxExpr>();
		final openNames = new Array<String>();
		final openParameters = new Array<HxLambdaSignature.HxLambdaParameter>();
		final ordered = new Array<HxExpr>();
		for (slot in 0...parameters.length) {
			final parameter = parameters[slot];
			if (parameter.isRest)
				return null;
			if (slot < arguments.length && !isPlaceholder(arguments[slot])) {
				if (needsConversion(arguments[slot], parameter.type))
					return null;
				final name = BOUND + slot;
				boundNames.push(name);
				boundValues.push(arguments[slot]);
				ordered.push(HxExpr.EIdent(name));
			} else if (slot >= arguments.length && parameter.isOptional) {
				// Upstream omits a trailing optional parameter that has no argument.
				break;
			} else {
				final name = OPEN + slot;
				openNames.push(name);
				openParameters.push({isOptional: parameter.isOptional, isRest: false, hasDefault: false});
				ordered.push(HxExpr.EIdent(name));
			}
		}
		final call:HxExpr = HxExpr.ECall(HxExpr.EIdent(CALLEE), ordered);
		final closure = arrow(openNames, new HxLambdaSignature(openParameters), call, position);
		// Like upstream's variables, locals hold the callee and each bound argument, evaluated in
		// order, once; their initializers give them exact types, so the closure's parameters infer
		// from the call to the callee.
		final statements:Array<HxExpr> = [declaration(CALLEE, callee, position)];
		for (slot in 0...boundNames.length)
			statements.push(declaration(boundNames[slot], boundValues[slot], position));
		statements.push(closure);
		return HxExpr.ESourceGroup(statements, position);
	}

	static function declaration(name:String, value:HxExpr, position:HxPos):HxExpr
		return HxExpr.EVars([HxExpr.EVariableDeclaration(name, "", value, position, true, false)]);

	/** An authored-shape arrow function, so capture analysis sees an ordinary source function. */
	static function arrow(names:Array<String>, signature:HxLambdaSignature, body:HxExpr, position:HxPos):HxExpr {
		return HxExpr.ESourceFunction(new HxSourceFunction({
			kind: Arrow,
			placement: Value,
			arguments: names,
			signature: signature
		}), body, [], position);
	}

	static function isPlaceholder(expression:HxExpr):Bool {
		switch expression {
			case EIdent(name):
				return name == "_";
			case _:
				return false;
		}
	}
}
