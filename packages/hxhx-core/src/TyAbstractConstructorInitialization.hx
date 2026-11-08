/**
	Require an abstract constructor to assign `this` before it can complete.

	Why
	- An abstract value is its backing value, and the constructor chooses it
	  with `this = value`. Upstream Haxe 4.3.7 rejects a constructor that can
	  finish, return, or read `this` before an assignment, with "Missing this =
	  value". The typer accepted such constructors, so a backend had to reject
	  them later or invent a value (haxe_ocaml-vitgz).

	What
	- `require` walks the parsed constructor body once, with one fact: whether
	  `this` is assigned on every path that reaches the current point.
	- The rules follow upstream's observable admission, recorded in
	  `test/oracle/constructor_initialization_seed/cases.json`:
	  - `if` without `else`, `while`, and `for` may skip their body, so
		assignments inside them do not count. A `do` body runs once and counts,
		and so does a `for` over a non-empty constant range or array literal,
		which upstream unrolls.
	  - Both branches of `if`/`else` and `?:`, every catch of `try`, and every
		case of a covering `switch` must assign.
	  - `return`, `throw`, `break` and `continue` end a path. A path that ends
		counts as assigned, but a `return` itself requires `this` to be assigned.
	  - Reading `this` (including `this += value`) before an assignment is
		rejected at the read.
	  - Operands are visited in order, so an assignment on the right of `&&`
		counts, as upstream accepts it.
	  - A nested function's assignment counts where the function is defined,
		as upstream treats it (`final set = v -> this = v;` is accepted). Reads
		inside it are not checked: upstream only warns when a closure captures
		`this` before the assignment.
	- An expression form this walk does not model counts as assigned. That keeps
	  the check from rejecting a valid constructor it cannot follow.
**/
class TyAbstractConstructorInitialization {
	static inline final MESSAGE = "Missing this = value";

	final filePath:String;

	/** Inside a nested function: its assignments count, but its reads and returns are not checked. */
	var nested = false;

	function new(filePath:String) {
		this.filePath = filePath;
	}

	/**
		Names in scope that the constructor itself declares: its parameters, and
		each local variable from its declaration to the end of its block. A range
		bound that names one of them is a run-time value, so upstream does not
		unroll that loop. A local declared later, or in a closed block, does not
		hide a same-named class constant.
	**/
	var runtimeNames = new Map<String, Bool>();

	/** Run `walk` in a nested lexical scope: locals it declares are forgotten afterwards. */
	function scoped<T>(walk:() -> T):T {
		final outer = runtimeNames.copy();
		final result = walk();
		runtimeNames = outer;
		return result;
	}

	/**
		Throw upstream's diagnostic when `body` can complete without assigning
		`this`. `runtimeNames` are names that are run-time values in the whole
		body: the parameters and the abstract's mutable static fields.
	**/
	public static function require(body:Array<HxStmt>, filePath:String, constructorPos:HxPos, ?parameterNames:Array<String>):Void {
		final checker = new TyAbstractConstructorInitialization(filePath);
		for (name in (parameterNames == null ? [] : parameterNames))
			checker.runtimeNames.set(name, true);
		if (!checker.statements(body, false, constructorPos))
			throw new TyperError(filePath, constructorPos, MESSAGE);
	}

	function fail(pos:HxPos):Bool {
		if (nested)
			return true;
		throw new TyperError(filePath, pos, MESSAGE);
	}

	/**
		A path that ends at `throw`, `break` or `continue` counts as assigned in the
		constructor itself. Inside a nested function, ending a path assigns
		nothing, so the function counts only when it assigns before it ends.
	**/
	function ends(assigned:Bool):Bool
		return nested ? assigned : true;

	function statements(body:Array<HxStmt>, assigned:Bool, pos:HxPos):Bool {
		var state = assigned;
		for (child in body)
			state = statement(child, state);
		return state;
	}

	/** Returns whether `this` is assigned after `s` on every path that continues. */
	function statement(s:HxStmt, assigned:Bool):Bool {
		return switch (s) {
			case SBlock(body, pos):
				scoped(() -> statements(body, assigned, pos));
			case SVar(name, _, init, pos):
				final state = init == null ? assigned : expression(init, assigned, pos);
				runtimeNames.set(name, true);
				state;
			case SIf(condition, whenTrue, whenFalse, pos):
				final afterCondition = expression(condition, assigned, pos);
				final trueState = statement(whenTrue, afterCondition);
				whenFalse == null ? afterCondition : trueState && statement(whenFalse, afterCondition);
			case SForIn(_, iterable, body, pos):
				final afterIterable = expression(iterable, assigned, pos);
				final afterBody = statement(body, afterIterable);
				runsAtLeastOnce(iterable) ? afterBody : afterIterable;
			case SForKeyValue(_, _, iterable, body, pos):
				final afterIterable = expression(iterable, assigned, pos);
				statement(body, afterIterable);
				afterIterable;
			case SWhile(condition, body, pos):
				final afterCondition = expression(condition, assigned, pos);
				statement(body, afterCondition);
				afterCondition;
			case SDoWhile(body, condition, pos):
				expression(condition, statement(body, assigned), pos);
			case SSwitch(scrutinee, patterns, bodies, pos, exhaustive):
				final afterScrutinee = expression(scrutinee, assigned, pos);
				var all = true;
				for (body in bodies)
					all = statement(body, afterScrutinee) && all;
				covers(patterns, exhaustive) ? all : afterScrutinee;
			case SGuardedSwitch(scrutinee, _, _, bodies, pos):
				final afterScrutinee = expression(scrutinee, assigned, pos);
				for (body in bodies)
					statement(body, afterScrutinee);
				afterScrutinee;
			case STry(body, catches, _):
				var all = statement(body, assigned);
				for (handler in catches)
					all = statement(handler.body, assigned) && all;
				all;
			case SBreak(_) | SContinue(_):
				ends(assigned);
			case SThrow(value, pos):
				ends(expression(value, assigned, pos));
			case SReturnVoid(pos):
				nested ? assigned : (assigned ? true : fail(pos));
			case SReturn(value, pos):
				final state = expression(value, assigned, pos);
				nested ? state : (state ? true : fail(pos));
			case SExpr(value, pos):
				expression(value, assigned, pos);
			case STargetScope(_, body, _):
				statement(body, assigned);
		};
	}

	/**
		Whether a `for` loop's body runs at least once for this iterable. Upstream
		unrolls loops over a constant range or an array literal, so their body's
		assignment counts (`for (i in 0...3) this = 3;` is accepted). Upstream
		unrolls only within a cost limit (`0...1000` is not unrolled); this check
		accepts every non-empty constant range rather than model that limit.
	**/
	function runsAtLeastOnce(iterable:HxExpr):Bool {
		return switch (iterable) {
			case EParenthesized(inner, _): runsAtLeastOnce(inner);
			case ERange(start, end):
				final first = literalBound(start);
				final last = literalBound(end);
				if (first != null && last != null) last > first; else !(notUnrolled(start) || notUnrolled(end));
			case EArrayDecl(values): values.length > 0;
			case _: false;
		};
	}

	/**
		An integer literal bound, optionally negated (`3`, `-1`). Upstream unrolls
		only bare constants: `(0)...(3)` and `-(1)...3` are not unrolled.
	**/
	static function literalBound(e:HxExpr):Null<Int> {
		return switch (e) {
			case EInt(value): value;
			case EUnop(Negate, _, EInt(value)): -value;
			case _: null;
		};
	}

	/**
		Whether upstream certainly does not unroll a loop over this bound: a
		parenthesized or computed bound (`(count())`, `COUNT + 1`), or a
		constructor parameter or local in scope. A bare name or call that may be
		an inline constant (`COUNT`, `count()`) is accepted rather than rejected;
		upstream unrolls those, but not a plain `static var`.
	**/
	function notUnrolled(e:HxExpr):Bool {
		return switch (e) {
			case EInt(_): false;
			case EUnop(Negate, _, EInt(_)): false;
			case EIdent(name): runtimeNames.exists(name);
			case EParenthesized(_, _) | EBinop(_, _, _) | ETernary(_, _, _) | EUnop(_, _, _): true;
			case _: false;
		};
	}

	/**
		A switch covers every value when an unguarded case is a catch-all, the
		unguarded cases name both Bool values, or every unguarded case is a
		constructor pattern. Guarded cases never cover, and they do not disqualify
		the unguarded ones (upstream accepts `case Some(v) if (v > 0): ...
		case Some(_): ... case None: ...`). A switch of only guarded cases does
		not cover.
	**/
	static function covers(patterns:Array<HxSwitchPattern>, exhaustive:Null<Bool>):Bool {
		if (exhaustive == true)
			return true;
		var sawTrue = false;
		var sawFalse = false;
		var sawConstructor = false;
		var sawOther = false;
		function visit(pattern:HxSwitchPattern):Void {
			switch (pattern) {
				case PWildcard | PBind(_):
					sawTrue = sawFalse = true;
				case PCapture(_, inner):
					visit(inner);
				case POr(items):
					for (item in items)
						visit(item);
				case PBool(true):
					sawTrue = true;
					sawOther = true;
				case PBool(false):
					sawFalse = true;
					sawOther = true;
				case PEnumValue(_) | PEnumExtract(_, _):
					sawConstructor = true;
				case PGuard(_, _):
				case _:
					sawOther = true;
			}
		}
		for (pattern in patterns)
			visit(pattern);
		// Constructor patterns: typing owns enum coverage. Count them as covering
		// rather than reject a constructor whose switch names every member.
		return (sawTrue && sawFalse) || (sawConstructor && !sawOther);
	}

	/** Returns whether `this` is assigned after evaluating `e`. */
	function expression(e:HxExpr, assigned:Bool, pos:HxPos):Bool {
		return switch (e) {
			case EThis:
				assigned ? true : fail(pos);
			case EBinop("=", EThis | EUntyped(EThis) | EParenthesized(EThis, _), value):
				// `untyped this = value` parses with the untyped marker on the destination.
				expression(value, assigned, pos);
				true;
			case EBinop(op, EThis, value) if (StringTools.endsWith(op, "=") && op != "==" && op != "!=" && op != "<=" && op != ">="):
				// `this op= value` reads `this` first.
				if (!assigned)
					fail(pos);
				expression(value, assigned, pos);
				true;
			case EBinop(_, left, right):
				expression(right, expression(left, assigned, pos), pos);
			case EParenthesized(inner, position) | EPrivateAccess(inner, position):
				expression(inner, assigned, position);
			case ECheckType(inner, _) | ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
				expression(inner, assigned, pos);
			case EUnop(_, _, operand):
				expression(operand, assigned, pos);
			case EField(object, _) | ENullSafeField(object, _):
				expression(object, assigned, pos);
			case ECall(callee, arguments):
				var state = expression(callee, assigned, pos);
				for (argument in arguments)
					state = expression(argument, state, pos);
				state;
			case ENew(_, arguments) | EArrayDecl(arguments):
				var state = assigned;
				for (argument in arguments)
					state = expression(argument, state, pos);
				state;
			case EArrayAccess(array, index):
				expression(index, expression(array, assigned, pos), pos);
			case EAnon(_, values):
				var state = assigned;
				for (value in values)
					state = expression(value, state, pos);
				state;
			case ETernary(condition, whenTrue, whenFalse): final afterCondition = expression(condition, assigned,
					pos); final trueState = expression(whenTrue, afterCondition, pos); expression(whenFalse, afterCondition, pos) && trueState;
			case ESourceIf(condition, whenTrue, whenFalse, position):
				final afterCondition = expression(condition, assigned, position);
				final trueState = expression(whenTrue, afterCondition, position);
				whenFalse == null ? afterCondition : expression(whenFalse, afterCondition, position) && trueState;
			case ESourceGroup(children, position):
				scoped(() -> {
					var state = assigned;
					for (child in children)
						state = expression(child, state, position);
					state;
				});
			case EVariableDeclaration(name, _, initializer, position, _, _):
				final state = initializer == null ? assigned : expression(initializer, assigned, position);
				runtimeNames.set(name, true);
				state;
			case EVars(declarations):
				var state = assigned;
				for (declaration in declarations)
					state = expression(declaration, state, pos);
				state;
			case EThrow(value, position):
				ends(expression(value, assigned, position));
			case EReturn(value):
				final state = value == null ? assigned : expression(value, assigned, pos);
				nested ? state : (state ? true : fail(pos));
			case EBreak(_) | EContinue(_):
				ends(assigned);
			case EWhile(condition, body, _, position, DoWhile):
				var state = assigned;
				for (child in body)
					state = expression(child, state, position);
				expression(condition, state, position);
			case EWhile(condition, body, _, position, Normal):
				final afterCondition = expression(condition, assigned, position);
				for (child in body)
					expression(child, afterCondition, position);
				afterCondition;
			case ESourceFor(_, iterable, body, position):
				final afterIterable = expression(iterable, assigned, position);
				final afterBody = expression(body, afterIterable, position);
				runsAtLeastOnce(iterable) ? afterBody : afterIterable;
			case ESourceTry(_, bodies, position):
				var all = bodies.length > 0;
				for (body in bodies)
					all = expression(body, assigned, position) && all;
				all;
			case ESwitch(scrutinee, patterns, bodies):
				final afterScrutinee = expression(scrutinee, assigned, pos);
				var all = true;
				for (body in bodies)
					all = expression(body, afterScrutinee, pos) && all;
				covers(patterns, null) ? all : afterScrutinee;
			case ELambda(_, body, _) | ESourceFunction(_, body, _, _): // Upstream counts an assignment inside a nested function where the
				// function is defined, as if it ran there (`final set = v -> this = v;`).
				// It only warns about reads, so reads and returns are not checked.
				final outer = nested; nested = true; final afterBody = expression(body, assigned, pos); nested = outer; assigned || afterBody;
			case ENull | EBool(_) | EString(_) | EInt(_) | EFloat(_) | EIdent(_) | EEnumValue(_) | ESuper | ERange(_, _) | EMacroType(_):
				assigned;
			case _:
				// A form this walk does not model: do not reject what it cannot follow.
				true;
		};
	}
}
