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

	public function new(positions:MacroSyntaxPositions) {
		if (positions == null)
			throw "macro syntax export requires call positions";
		this.positions = positions;
	}

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

	function child(expression:HxExpr, position:Position):Expr
		return convert(expression, position);

	function optionalChild(expression:Null<HxExpr>, position:Position):Null<Expr>
		return expression == null ? null : convert(expression, position);

	function definition(expression:HxExpr, position:Position):ExprDef {
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
			case EString(value):
				EConst(CString(value, DoubleQuotes));
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
			case ESwitch(_, _, _) | ESwitchRaw(_):
				throw failure("switch expressions are not exported yet; their patterns have no public macro form here");
			case EArrayComprehension(_, _, _, _):
				throw failure("array comprehensions are not exported yet (haxe_ocaml-20jan)");
			case ETryCatchRaw(_) | EUnsupported(_):
				throw failure("unparsed raw syntax cannot be given to a macro");
			case EMacroExpr(_, _) | EMacroType(_):
				throw failure("macro reification inside a macro argument is not exported yet");
		};
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
