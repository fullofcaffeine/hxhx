import haxe.macro.Expr;

/**
	Convert the authored argument syntax of one macro call (`HxExpr`) to `haxe.macro.Expr`.

	When hxhx runs a project expression macro, the macro must see the syntax the author wrote,
	not a typed or lowered form. For example `Identity.preserve(function(label:String):String {
	{ return label; } })` gives the macro an `EFunction(FAnonymous, ...)` whose body is an
	`EBlock` that contains the nested `EBlock`. The parser keeps that structure as
	`ESourceFunction` and `ESourceGroup`; this exporter maps it to the public enum.

	Positions: a node with its own known `HxPos` gets a zero-width position at its start in the
	call file (`MacroSyntaxPositions`). A node without its own position, such as an identifier or
	a `return`, reuses the position of its nearest enclosing node that has one. That reuse is an
	approximation, documented in `docs/00-project/EXPRESSION_MACRO_ARGUMENT_PLAN.md` and owned by
	`haxe_ocaml-9sj5p.2`. An argument whose root has no known position fails explicitly, because
	nothing in it could be placed in the source.

	Failure policy: syntax that has no public macro form in this exporter (pattern switches,
	comprehensions, unparsed raw text, lowered sequences without source groups, `is`) throws a
	message that starts with `macro syntax export:`. It is never flattened to source text.
**/
class MacroSyntaxExport {
	final positions:MacroSyntaxPositions;
	final splice:Null<MacroSyntaxSpliceHook>;

	/**
		`splice` is consulted before every node. A macro quotation (`macro ...`) passes one that
		recognizes the parser's splice markers (`$i{}`, `$e{}`, ...) and returns the public form
		of a hole; it returns null for ordinary syntax. Macro arguments pass none: a marker there
		is a parse error upstream and is exported as the identifier the parser produced.
	**/
	public function new(positions:MacroSyntaxPositions, ?splice:MacroSyntaxSpliceHook) {
		if (positions == null)
			throw "macro syntax export requires call positions";
		this.positions = positions;
		this.splice = splice;
	}

	/**
		Export quoted syntax. Unlike an argument, a quote (`macro 1 + 2`) owns no position of its
		own; `inherited` is the position every quoted node without one receives, usually that of
		the statement containing the quote.
	**/
	public function quotation(expression:HxExpr, inherited:Position):Expr
		return convert(expression, inherited);

	/** Export the argument at `index`; its root syntax must own a known source position. */
	public function argument(expression:HxExpr, index:Int):Expr {
		final own = ownPosition(expression);
		if (own == null)
			throw failure("argument "
				+ index
				+ " has no recorded source position; only syntax that starts a group, function, loop, branch,"
				+ " parenthesis, or declaration owns one");
		return convert(expression, positions.export(own));
	}

	function convert(expression:HxExpr, inherited:Position):Expr {
		if (expression == null)
			throw failure("missing expression");
		final own = ownPosition(expression);
		final position = own == null ? inherited : positions.export(own);
		return {expr: definition(expression, position), pos: position};
	}

	/** Expression metadata arguments as written (`Off`, `a, f(b, c)`), split at top-level commas. */
	static function metadataArguments(text:String):Array<HxExpr> {
		final parts = new Array<String>();
		var depth = 0;
		var start = 0;
		for (index in 0...text.length) {
			switch text.charAt(index) {
				case "(" | "[" | "{":
					depth++;
				case ")" | "]" | "}":
					depth--;
				case "," if (depth == 0):
					parts.push(text.substring(start, index));
					start = index + 1;
				case _:
			}
		}
		parts.push(text.substr(start));
		return [
			for (part in parts)
				if (StringTools.trim(part).length > 0) HxParser.parseCompleteExprText(StringTools.trim(part))
		];
	}

	function child(expression:HxExpr, position:Position):Expr
		return convert(expression, position);

	function optionalChild(expression:Null<HxExpr>, position:Position):Null<Expr>
		return expression == null ? null : convert(expression, position);

	function definition(expression:HxExpr, position:Position):ExprDef {
		if (splice != null) {
			final spliced = splice(expression, value -> child(value, position));
			if (spliced != null)
				return spliced;
		}
		return switch expression {
			case EPrivateAccess(_, _) | EParenthesized(_, _) | ESourceGroup(_, _) | ESourceFunction(_, _, _, _) | ESourceIf(_, _, _, _) |
				ESourceFor(_, _, _, _) | ESourceTry(_, _, _) | HxExpr.EThrow(_, _) | HxExpr.EWhile(_, _, _, _, _):
				final converted = HxSourceMacroSyntax.definition(expression, value -> child(value, position), hint -> typeOrNull(hint, position),
					writtenMetadata);
				if (converted == null)
					throw failure("authored control syntax has no public macro form");
				converted;
			case EDiscardThen(_, _) | ELoweredControl(_, _, _, _):
				throw failure(HxMacroBlockBoundary.missingSourceGroup);
			case ENull:
				EConst(CIdent("null"));
			case EBool(value):
				EConst(CIdent(value ? "true" : "false"));
			case EString(value, true):
				EConst(CString(value, SingleQuotes));
			case EString(value, _):
				EConst(CString(value, DoubleQuotes));
			case ERegexLiteral(pattern, flags):
				EConst(CRegexp(pattern, flags));
			case EInt(value):
				EConst(CInt(Std.string(value), null));
			case EFloat(value):
				EConst(CFloat(Std.string(value), null));
			case EEnumValue(name) | EIdent(name):
				EConst(CIdent(name));
			case EThis:
				EConst(CIdent("this"));
			case ESuper:
				EConst(CIdent("super"));
			case EField(owner, field):
				EField(child(owner, position), field, Normal);
			case ENullSafeField(owner, field):
				EField(child(owner, position), field, Safe);
			case ECall(EIdent("__hxhx_spread"), [inner]):
				EUnop(OpSpread, false, child(inner, position));
			case ECall(EIdent("__hxhx_int_literal"), [EString(raw), EString(suffix)]):
				EConst(CInt(raw, suffix));
			case ECall(EIdent("__hxhx_float_literal"), [EString(raw), EString(suffix)]):
				EConst(CFloat(raw, suffix));
			// Ordinary parsing drops a written colon from expression metadata (`__hxhx_expr_meta`), so
			// there only a name with its colon is exact: the parser writes one for a markup literal.
			case ECall(EIdent(marker), [EString(name), EString(argumentText), inner])
				if (marker == HxAuthoredSyntax.META || (marker == "__hxhx_expr_meta" && StringTools.startsWith(name, ":"))):
				EMeta({name: name, params: [for (argument in metadataArguments(argumentText)) child(argument, position)], pos: position},
					child(inner, position));
			case ECall(EIdent(marker), _) if (StringTools.startsWith(marker, "__hxhx_")):
				throw failure("the parser marker `" + marker + "` has no public macro form");
			case ECall(callee, arguments):
				ECall(child(callee, position), [for (argument in arguments) child(argument, position)]);
			case ETernary(condition, whenTrue, whenFalse):
				ETernary(child(condition, position), child(whenTrue, position), child(whenFalse, position));
			case EAnon(names, values):
				if (names.length != values.length)
					throw failure("object literal field names and values differ in length");
				EObjectDecl([
					for (index in 0...names.length)
						{field: names[index], expr: child(values[index], position), quotes: Unquoted}
				]);
			case EArrayDecl(values):
				EArrayDecl([for (value in values) child(value, position)]);
			case EArrayAccess(array, index):
				EArray(child(array, position), child(index, position));
			case ENew(typePath, arguments):
				ENew(typePathOf(typePath, position), [for (argument in arguments) child(argument, position)]);
			case ECast(inner, typeHint):
				ECast(child(inner, position), typeOrNull(typeHint, position));
			case ECheckType(inner, typeHint):
				final type = typeOrNull(typeHint, position);
				if (type == null)
					throw failure("type check without a written type");
				ECheckType(child(inner, position), type);
			case EUntyped(inner):
				EUntyped(child(inner, position));
			case ELambda(arguments, body):
				EFunction(FArrow, {
					args: [
						for (name in arguments)
							{
								name: name,
								type: null,
								opt: false,
								value: null,
								meta: null
							}
					],
					ret: null,
					expr: child(body, position),
					params: []
				});
			case EUnop(op, fixity, inner):
				HxUnaryOperatorTools.requireValidFixity(op, fixity);
				EUnop(unop(op), fixity == Postfix, child(inner, position));
			case EBinop(op, left, right):
				EBinop(binop(op), child(left, position), child(right, position));
			case ERange(left, right):
				EBinop(OpInterval, child(left, position), child(right, position));
			case EReturn(value):
				EReturn(optionalChild(value, position));
			case EVars(declarations):
				EVars([for (declaration in declarations) variable(declaration, position)]);
			case EVariableDeclaration(_, _, _, _, _, _):
				throw failure("a variable declaration outside its declaration list");
			case EBreak(_):
				EBreak;
			case EContinue(_):
				EContinue;
			case ESwitch(subject, patterns, bodies, defaultArm):
				switchDefinition(subject, patterns, bodies, defaultArm, position);
			case ESwitchRaw(_):
				throw failure("an unparsed switch has no public macro form");
			case EArrayComprehension(_, _, _, _):
				throw failure("array comprehensions are not exported yet (haxe_ocaml-20jan)");
			case ETryCatchRaw(_) | EUnsupported(_):
				throw failure("unparsed raw syntax cannot be given to a macro");
			case EMacroType(typeText):
				// Upstream turns `macro : T` into construction syntax while it parses.
				MacroTypeQuotation.expression(typeText, position).expr;
			case EMacroExpr(_, _):
				throw failure("macro reification inside a macro argument is not exported yet");
		};
	}

	/**
		`switch e { case p1, p2 if (g): body; default: d }` as upstream parses it: one case per arm with
		its pattern expressions (a comma list gives several), its guard, and its body as a block, or
		null when the arm is empty; the arm written `default:` is the separate default. Every pattern
		node receives the position of its arm's body, which lets an empty arm come back with its
		position when the syntax is imported.
	**/
	function switchDefinition(subject:HxExpr, patterns:Array<HxSwitchPattern>, bodies:Array<HxExpr>, defaultArm:Null<Int>, position:Position):ExprDef {
		if (patterns.length != bodies.length)
			throw failure("switch patterns and bodies differ in length");
		final cases = new Array<Case>();
		var otherwise:Null<Expr> = null;
		for (index in 0...patterns.length) {
			final body = bodies[index];
			final armPosition = switch body {
				case ESourceGroup(_, own) if (MacroSyntaxPositions.isKnown(own)): positions.export(own);
				case _: position;
			};
			final empty = body.match(ESourceGroup([], _));
			if (defaultArm != null && index == defaultArm) {
				// Upstream's macro view of an empty `default:` is a null default, as for no default.
				otherwise = empty ? null : child(body, armPosition);
				continue;
			}
			var pattern = patterns[index];
			var guard:Null<Expr> = null;
			switch pattern {
				case PGuard(inner, condition):
					pattern = inner;
					guard = child(condition, armPosition);
				case _:
			}
			final values = switch pattern {
				case POr(alternatives, true): [for (alternative in alternatives) patternExpr(alternative, armPosition)];
				case _: [patternExpr(pattern, armPosition)];
			};
			cases.push({values: values, guard: guard, expr: empty ? null : child(body, armPosition)});
		}
		return ESwitch(child(subject, position), cases, otherwise);
	}

	/** One case pattern as the expression upstream parses. */
	function patternExpr(pattern:HxSwitchPattern, position:Position):Expr {
		inline function make(definition:ExprDef):Expr
			return {expr: definition, pos: position};
		function path(name:String):Expr {
			final parts = name.split(".");
			var result = make(EConst(CIdent(parts[0])));
			for (index in 1...parts.length)
				result = make(EField(result, parts[index], Normal));
			return result;
		}
		final definition:ExprDef = switch pattern {
			case PNull: EConst(CIdent("null"));
			case PWildcard: EConst(CIdent("_"));
			case PBool(value): EConst(CIdent(value ? "true" : "false"));
			case PString(value): EConst(CString(value, DoubleQuotes));
			case PInt(_, text) if (text != null): EField(make(EConst(CString(text, DoubleQuotes))), "code", Normal);
			case PInt(value, _): EConst(CInt(Std.string(value), null));
			case PFloat(text): EConst(CFloat(text, null));
			case PEnumValue(name, _) if (StringTools.startsWith(name, "macro:")):
				throw failure("a `macro :T` case pattern is not exported yet");
			case PEnumValue(name, true): ECast(path(name), null);
			case PEnumValue(name, _): path(name).expr;
			case PEnumExtract(name, arguments, _): ECall(path(name), [for (argument in arguments) patternExpr(argument, position)]);
			// Upstream parses `{}` as an empty block, not an empty object.
			case PObject([], []): EBlock([]);
			case PObject(names, fields):
				if (names.length != fields.length)
					throw failure("object pattern names and patterns differ in length");
				EObjectDecl([
					for (index in 0...names.length)
						{field: names[index], expr: patternExpr(fields[index], position), quotes: Unquoted}
				]);
			// `case var x:` and `case x = _:` read the same; upstream's spelling is `var x`.
			case PCapture(name, PWildcard): EVars([{name: name, type: null, expr: null}]);
			case PCapture(name, inner): EBinop(OpAssign, make(EConst(CIdent(name))), patternExpr(inner, position));
			case PArray(items): EArrayDecl([for (item in items) patternExpr(item, position)]);
			case PBind(name): EConst(CIdent(name));
			case POr(alternatives, _):
				if (alternatives.length == 0)
					throw failure("an empty or-pattern");
				function alternative(item:HxSwitchPattern):Expr {
					final exported = patternExpr(item, position);
					// The parser drops written parentheses but keeps their grouping as a nested or-pattern.
					return item.match(POr(_, _)) ? make(EParenthesis(exported)) : exported;
				}
				var combined = alternative(alternatives[0]);
				for (index in 1...alternatives.length)
					combined = make(EBinop(OpOr, combined, alternative(alternatives[index])));
				combined.expr;
			case PGuard(_, _): throw failure("a guard nested inside a pattern");
			case PExtractor(_, _): throw failure("extractor patterns are not exported to macros yet");
			case PUnsupportedPattern(_): throw failure("the parser did not understand this pattern");
		};
		return make(definition);
	}

	function variable(declaration:HxExpr, inherited:Position):Var {
		return switch declaration {
			case EVariableDeclaration(name, typeHint, initializer, declared, isFinal, isStatic):
				final namePosition = MacroSyntaxPositions.isKnown(declared) ? positions.export(declared) : inherited;
				{
					name: name,
					namePos: namePosition,
					type: typeOrNull(typeHint, namePosition),
					expr: optionalChild(initializer, namePosition),
					isFinal: isFinal,
					isStatic: isStatic,
					meta: []
				};
			case _:
				throw failure("a declaration list contains a non-declaration");
		};
	}

	/** Written annotations are stored as compact text; read them with the shared type grammar. */
	static function typeOrNull(typeHint:Null<String>, position:Position):Null<ComplexType> {
		final text = typeHint == null ? "" : StringTools.trim(typeHint);
		if (text.length == 0)
			return null;
		final parsed = try {
			HxTypedefParser.parseTypeHint(text);
		} catch (error:HxParseError) {
			throw failure("written type `" + text + "` could not be read: " + error.message);
		}
		return HxMacroTypeSyntax.convert(parsed, position, writtenMetadata);
	}

	static function typePathOf(typeHint:String, position:Position):TypePath {
		final type = typeOrNull(typeHint, position);
		if (type == null)
			throw failure("constructor call without a type");
		final written:ComplexType = type;
		return switch written {
			case TPath(path): path;
			case _: throw failure("constructor type `" + typeHint + "` is not a type path");
		};
	}

	static function writtenMetadata(entries:Array<String>):Metadata
		throw failure("written metadata inside types or type parameters is not exported yet");

	static function binop(token:String):Binop {
		return switch token {
			case "is": throw failure("the `is` operator is not exported yet; the parser keeps its type as an expression");
			case _: HxMacroBinaryOperator.parse(token);
		};
	}

	static function unop(op:HxUnaryOperator):Unop {
		return switch op {
			case Increment: OpIncrement;
			case Decrement: OpDecrement;
			case Negate: OpNeg;
			case LogicalNot: OpNot;
			case BitwiseNot: OpNegBits;
		};
	}

	/** The parser records a start position on these source nodes only. */
	static function ownPosition(expression:HxExpr):Null<HxPos> {
		final position = switch expression {
			case EParenthesized(_, position) | ESourceTry(_, _, position) | ESourceFor(_, _, _, position) | ELoweredControl(_, _, _, position) |
				ESourceIf(_, _, _, position) |
				HxExpr.EThrow(_,
					position) | EVariableDeclaration(_, _, _, position, _,
						_) | HxExpr.EWhile(_, _, _, position,
						_) | EBreak(position) | EContinue(position) | ESourceGroup(_,
							position) | ESourceFunction(_, _, _, position) | EPrivateAccess(_, position):
				position;
			case _: null;
		};
		return MacroSyntaxPositions.isKnown(position) ? position : null;
	}

	static function failure(message:String):String
		return StringTools.startsWith(message, "macro syntax export:") ? message : "macro syntax export: " + message;
}

/** See `MacroSyntaxExport.new`: `child` converts an ordinary nested node with the current position. */
typedef MacroSyntaxSpliceHook = (expression:HxExpr, child:HxExpr->Expr) -> Null<ExprDef>;
