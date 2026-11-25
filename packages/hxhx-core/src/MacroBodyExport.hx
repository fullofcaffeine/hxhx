import haxe.macro.Expr;

/**
	Convert parsed function bodies and field initializers (`HxStmt`, `HxExpr`) to `haxe.macro.Expr`.

	Why
	- `MacroSyntaxExport` converts the authored argument of one macro call. Whole function bodies
	  are parsed as statements (`HxStmt`), and bodies often contain pattern switches, which a macro
	  argument does not need yet.
	- Two consumers need whole bodies in the public shape: the frontend parse oracle, which
	  compares hxhx's parse of a file with upstream Haxe's parse of the same file, and later
	  `Context.getBuildFields()` for build macros.

	What
	- `functionBody` converts the statements of one function. A body written with braces becomes
	  an `EBlock`; a body written as one expression (`function f() return x;`) becomes that
	  expression, as upstream Haxe parses it.
	- `fieldInitializer` converts the initializer of a variable or property field.
	- Switches export with their patterns. A wildcard or `default` case becomes `case _:`, so both
	  spellings compare equal; they mean the same thing.

	Failure policy
	- Syntax without an exact public form here (typed switch plans, target scopes, extractor
	  patterns kept as text, unsupported patterns, metadata on locals) throws a message that
	  starts with `macro syntax export:`. It is never approximated, so the oracle never reports a
	  false match.
**/
class MacroBodyExport {
	final positions:MacroSyntaxPositions;
	final expressions:MacroSyntaxExport;

	public function new(positions:MacroSyntaxPositions) {
		this.positions = positions;
		expressions = new MacroSyntaxExport(positions, (expression, child) -> splice(expression, child));
	}

	/** Convert one function body; `braced` says whether the source wrote it inside `{ }`. */
	public function functionBody(statements:Array<HxStmt>, braced:Bool, inherited:Position):Expr {
		if (!braced && statements.length == 1)
			return statement(statements[0], inherited);
		return {expr: EBlock([for (item in statements) statement(item, inherited)]), pos: inherited};
	}

	/** Convert the initializer of a variable or property field. */
	public function fieldInitializer(value:HxExpr, inherited:Position):Expr
		return expressions.quotation(value, inherited);

	function expression(value:HxExpr, inherited:Position):Expr
		return expressions.quotation(value, inherited);

	function statement(item:HxStmt, inherited:Position):Expr {
		final own = statementPosition(item);
		final position = MacroSyntaxPositions.isKnown(own) ? positions.export(own) : inherited;
		return {expr: statementDefinition(item, position), pos: position};
	}

	/** One declarator of a local variable statement. **/
	function declarator(item:HxStmt, position:Position):Var {
		return switch item {
			case SVar(name, typeHint, initializer, _, metadata):
				if (metadata != null && metadata.length > 0)
					throw failure("metadata on a local variable is not exported yet");
				{
					name: name,
					type: typeOrNull(typeHint, position),
					expr: initializer == null ? null : expression(initializer, position)
				};
			case _:
				throw failure("a declaration group holds a non-declaration statement");
		};
	}

	function statementDefinition(item:HxStmt, position:Position):ExprDef {
		return switch item {
			case SBlock(statements, _, true):
				// One `var a = 1, b = 2;` statement from authored parsing.
				EVars([for (child in statements) declarator(child, position)]);
			case SBlock(statements, _):
				EBlock([for (child in statements) statement(child, position)]);
			case SVar(_, _, _, _, _):
				EVars([declarator(item, position)]);
			case SIf(condition, whenTrue, whenFalse, _):
				EIf(expression(condition, position), statement(whenTrue, position), whenFalse == null ? null : statement(whenFalse, position));
			case SForIn(name, iterable, body, _):
				EFor(binop(OpIn, ident(name, position), expression(iterable, position), position), statement(body, position));
			case SForKeyValue(keyName, valueName, iterable, body, _):
				final pair = binop(OpArrow, ident(keyName, position), ident(valueName, position), position);
				EFor(binop(OpIn, pair, expression(iterable, position), position), statement(body, position));
			case SWhile(condition, body, _):
				EWhile(expression(condition, position), statement(body, position), true);
			case SDoWhile(body, condition, _):
				EWhile(expression(condition, position), statement(body, position), false);
			case SSwitch(scrutinee, patterns, bodies, _, _):
				switchDefinition(expression(scrutinee, position), patterns, [for (body in bodies) statement(body, position)], position);
			case SGuardedSwitch(_, _, _, _, _):
				throw failure("a typed guarded switch plan is not parser syntax");
			case STry(body, catches, _):
				ETry(statement(body, position), [
					for (handler in catches)
						{
							name: handler.name,
							type: typeOrNull(handler.typeHint, position),
							expr: statement(handler.body, position)
						}
				]);
			case SBreak(_):
				EBreak;
			case SContinue(_):
				EContinue;
			case SThrow(value, _):
				EThrow(expression(value, position));
			case SReturnVoid(_):
				EReturn(null);
			case SReturn(value, _):
				EReturn(expression(value, position));
			case SExpr(value, _):
				expression(value, position).expr;
			case STargetScope(_, _, _):
				throw failure("a native target scope has no public macro form");
		};
	}

	/** `MacroSyntaxExport` asks this hook before each expression node. */
	function splice(value:HxExpr, child:HxExpr->Expr):Null<ExprDef> {
		return switch value {
			case ESwitch(scrutinee, patterns, bodies):
				final position = child(scrutinee).pos;
				switchDefinition(child(scrutinee), patterns, [for (body in bodies) child(body)], position);
			case _:
				null;
		};
	}

	function switchDefinition(scrutinee:Expr, patterns:Array<HxSwitchPattern>, bodies:Array<Expr>, position:Position):ExprDef {
		if (patterns.length != bodies.length)
			throw failure("switch patterns and bodies differ in length");
		final cases:Array<Case> = [];
		for (index in 0...patterns.length) {
			var pattern = patterns[index];
			var guard:Null<Expr> = null;
			switch pattern {
				case PGuard(inner, condition):
					pattern = inner;
					guard = expression(condition, position);
				case _:
			}
			cases.push({values: [patternExpr(pattern, position)], guard: guard, expr: bodies[index]});
		}
		return ESwitch(scrutinee, cases, null);
	}

	function patternExpr(pattern:HxSwitchPattern, position:Position):Expr {
		final definition:ExprDef = switch pattern {
			case PNull: EConst(CIdent("null"));
			case PWildcard: EConst(CIdent("_"));
			case PBool(value): EConst(CIdent(value ? "true" : "false"));
			case PString(value): EConst(CString(value, DoubleQuotes));
			case PInt(_, text) if (text != null): EField({expr: EConst(CString(text, DoubleQuotes)), pos: position}, "code");
			case PInt(value, _): EConst(CInt(Std.string(value), null));
			case PFloat(text): EConst(CFloat(text, null));
			case PEnumValue(name, true): ECast(path(name, position), null);
			case PEnumValue(name, _): path(name, position).expr;
			case PEnumExtract(name, arguments, _):
				ECall(path(name, position), [for (argument in arguments) patternExpr(argument, position)]);
			case PObject(names, fields):
				if (names.length != fields.length)
					throw failure("object pattern names and patterns differ in length");
				EObjectDecl([
					for (index in 0...names.length)
						{field: names[index], expr: patternExpr(fields[index], position), quotes: Unquoted}
				]);
			case PCapture(name, PWildcard): EConst(CIdent(name));
			case PCapture(name, inner): EBinop(OpAssign, ident(name, position), patternExpr(inner, position));
			case PArray(items): EArrayDecl([for (item in items) patternExpr(item, position)]);
			case PBind(name): EConst(CIdent(name));
			case POr(alternatives):
				if (alternatives.length == 0)
					throw failure("an empty or-pattern");
				var combined = patternExpr(alternatives[0], position);
				for (index in 1...alternatives.length)
					combined = binop(OpOr, combined, patternExpr(alternatives[index], position), position);
				combined.expr;
			case PGuard(_, _): throw failure("a guard nested inside a pattern");
			case PExtractor(_, _): throw failure("extractor patterns are kept as text and are not exported yet");
			case PUnsupportedPattern(_): throw failure("the parser did not understand this pattern");
		};
		return {expr: definition, pos: position};
	}

	static function ident(name:String, position:Position):Expr
		return {expr: EConst(CIdent(name)), pos: position};

	/** A dotted name such as `haxe.ds.Option.Some` as a field-access chain. */
	static function path(name:String, position:Position):Expr {
		final parts = name.split(".");
		var result = ident(parts[0], position);
		for (index in 1...parts.length)
			result = {expr: EField(result, parts[index], Normal), pos: position};
		return result;
	}

	static function binop(op:Binop, left:Expr, right:Expr, position:Position):Expr
		return {expr: EBinop(op, left, right), pos: position};

	static function typeOrNull(typeHint:Null<String>, position:Position):Null<ComplexType> {
		final text = typeHint == null ? "" : StringTools.trim(typeHint);
		if (text.length == 0)
			return null;
		final parsed = try {
			HxTypedefParser.parseTypeHint(text);
		} catch (error:HxParseError) {
			throw failure("written type `" + text + "` could not be read: " + error.message);
		}
		return HxMacroTypeSyntax.convert(parsed, position, _ -> throw failure("written metadata inside types is not exported yet"));
	}

	static function statementPosition(item:HxStmt):Null<HxPos> {
		return switch item {
			case SBlock(_, position) | SVar(_, _, _, position, _) | SIf(_, _, _, position) | SForIn(_, _, _, position) | SForKeyValue(_, _, _, _, position) |
				SWhile(_, _, position) | SDoWhile(_, _, position) | SSwitch(_, _, _, position, _) | SGuardedSwitch(_, _, _, _, position) |
				STry(_, _, position) | SBreak(position) | SContinue(position) | SThrow(_, position) | SReturnVoid(position) | SReturn(_, position) |
				SExpr(_, position) | STargetScope(_, _, position):
				position;
		};
	}

	static function failure(message:String):String
		return StringTools.startsWith(message, "macro syntax export:") ? message : "macro syntax export: " + message;
}
