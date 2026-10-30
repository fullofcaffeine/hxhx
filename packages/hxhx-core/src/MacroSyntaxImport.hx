import haxe.macro.Expr;
import HxSourceFunction.HxSourceFunctionKind;
import HxSourceFunction.HxSourceFunctionPlacement;
import HxLambdaSignature.HxLambdaParameter;

/**
	Convert the `haxe.macro.Expr` a macro returned back into parser syntax (`HxExpr`).

	The compiler inserts the result in place of the macro call and then types it like code the
	author wrote. The importer therefore produces the same `HxExpr` forms the parser produces for
	the equivalent source: `EBlock` becomes `ESourceGroup`, `EFunction` becomes `ESourceFunction`
	with its written signature, `EIf` becomes `ESourceIf`, and so on. For the identity macro this
	means `import(export(argument))` is the original argument, which the round-trip tests check
	with the parser's exact body fingerprint.

	Totality: every `ExprDef` constructor is handled. Constructors with no faithful parser form
	yet (`ESwitch`, `EDisplay`, `EIs`, metadata other than `@:privateAccess`, local functions with
	type parameters, typed constants with suffixes) are rejected with a message that starts with
	`macro syntax import:`. The caller turns it into a compile error at the macro call.

	Positions: a returned position that this call exported restores the original `HxPos`. Any
	other position falls back to the call's first argument start, or to `HxPos.unknown()` when the
	call had no positioned argument (see `MacroSyntaxPositions`).

	Type annotations are printed back to the compact text form the parser stores
	(`Map<String,Int>`, `(Int,String)->Void`).
**/
class MacroSyntaxImport {
	final positions:MacroSyntaxPositions;

	public function new(positions:MacroSyntaxPositions) {
		if (positions == null)
			throw "macro syntax import requires call positions";
		this.positions = positions;
	}

	/** Import the expression a macro returned. */
	public function result(expression:Expr):HxExpr
		return convert(expression, false);

	function position(expression:Expr):HxPos {
		final restored = positions.resolve(expression.pos);
		if (restored != null)
			return restored;
		final anchor = positions.getAnchor();
		return anchor == null ? HxPos.unknown() : anchor;
	}

	function optional(expression:Null<Expr>):Null<HxExpr>
		return expression == null ? null : convert(expression, false);

	function values(expressions:Null<Array<Expr>>):Array<HxExpr> {
		if (expressions == null)
			throw failure("an expression list is missing");
		return [for (expression in expressions) convert(expression, false)];
	}

	function statements(expressions:Null<Array<Expr>>):Array<HxExpr> {
		if (expressions == null)
			throw failure("a block has no expression list");
		return [for (expression in expressions) convert(expression, true)];
	}

	/** `statement` is true for direct block entries, where a named function is a local declaration. */
	function convert(expression:Null<Expr>, statement:Bool):HxExpr {
		if (expression == null)
			throw failure("a required expression is missing");
		final definition = expression.expr;
		if (definition == null)
			throw failure("an expression has no definition");
		return switch definition {
			case EConst(constant):
				constantOf(constant, false);
			case EArray(array, index):
				EArrayAccess(convert(array, false), convert(index, false));
			case EBinop(OpInterval, left, right):
				ERange(convert(left, false), convert(right, false));
			case EBinop(op, left, right):
				EBinop(binopToken(op), convert(left, false), convert(right, false));
			case EField(owner, field, kind):
				final target = fieldOwner(owner);
				kind == Safe ? ENullSafeField(target, field) : EField(target, field);
			case EParenthesis(inner):
				EParenthesized(convert(inner, false), position(expression));
			case EObjectDecl(fields):
				if (fields == null)
					throw failure("an object literal has no field list");
				final names = new Array<String>();
				final fieldValues = new Array<HxExpr>();
				for (field in fields) {
					names.push(field.field);
					fieldValues.push(convert(field.expr, false));
				}
				EAnon(names, fieldValues);
			case EArrayDecl(entries):
				EArrayDecl(values(entries));
			case ECall(callee, arguments):
				ECall(convert(callee, false), values(arguments));
			case ENew(path, arguments):
				ENew(typePathText(path), values(arguments));
			case EUnop(op, postFix, inner):
				final converted = unop(op);
				final fixity:HxUnaryFixity = postFix ? Postfix : Prefix;
				HxUnaryOperatorTools.requireValidFixity(converted, fixity);
				EUnop(converted, fixity, convert(inner, false));
			case EVars(variables):
				if (variables == null)
					throw failure("a variable declaration has no variable list");
				EVars([for (variable in variables) declaration(variable, expression)]);
			case EFunction(kind, body):
				sourceFunction(kind, body, statement, expression);
			case EBlock(entries):
				ESourceGroup(statements(entries), position(expression));
			case EFor(iterator, body):
				sourceFor(iterator, body, expression);
			case EIf(condition, whenTrue, whenFalse):
				ESourceIf(convert(condition, false), convert(whenTrue, false), optional(whenFalse), position(expression));
			case EWhile(condition, body, normalWhile):
				if (body == null)
					throw failure("a while loop has no body");
				final loopBody:ExprDef = body.expr;
				final isBlock = switch loopBody {
					case EBlock(_): true;
					case _: false;
				};
				final entries = switch loopBody {
					case EBlock(children): statements(children);
					case _: [convert(body, false)];
				};
				HxExpr.EWhile(convert(condition, false), entries, isBlock, position(expression), normalWhile ? Normal : DoWhile);
			case ESwitch(_, _, _):
				throw failure("switch expressions are not imported yet; their patterns need the parser's pattern model");
			case ETry(body, catches):
				if (catches == null || catches.length == 0)
					throw failure("a try expression has no catch");
				final handlers = new Array<HxSourceCatch>();
				final bodies = [convert(body, false)];
				for (entry in catches) {
					handlers.push(new HxSourceCatch(entry.name, entry.type == null ? "" : typeText(entry.type), position(entry.expr)));
					bodies.push(convert(entry.expr, false));
				}
				ESourceTry(handlers, bodies, position(expression));
			case EReturn(value):
				EReturn(optional(value));
			case EBreak:
				EBreak(position(expression));
			case EContinue:
				EContinue(position(expression));
			case EUntyped(inner):
				EUntyped(convert(inner, false));
			case EThrow(value):
				HxExpr.EThrow(convert(value, false), position(expression));
			case ECast(inner, type):
				ECast(convert(inner, false), type == null ? "" : typeText(type));
			case EDisplay(_, _):
				throw failure("display requests cannot be returned by a macro");
			case ETernary(condition, whenTrue, whenFalse):
				ETernary(convert(condition, false), convert(whenTrue, false), convert(whenFalse, false));
			case ECheckType(inner, type):
				ECheckType(convert(inner, false), typeText(type));
			case EMeta(entry, inner):
				if (entry.name != ":privateAccess" || (entry.params != null && entry.params.length != 0))
					throw failure("metadata `@" + entry.name + "` on an expression is not imported yet; only `@:privateAccess` is kept by the parser");
				EPrivateAccess(convert(inner, false), position(expression));
			case EIs(_, _):
				throw failure("the `is` operator is not imported yet");
		};
	}

	/** The parser keeps `Owner` in `Owner.field` as a plain identifier, never as an enum value. */
	function fieldOwner(owner:Expr):HxExpr {
		if (owner == null || owner.expr == null)
			throw failure("a field access has no owner");
		return switch owner.expr {
			case EConst(constant): constantOf(constant, true);
			case _: convert(owner, false);
		};
	}

	/** Match the parser: `true`, `false`, `null`, `this`, `super` are literals; `Upper` names alone are enum values. */
	static function constantOf(constant:Constant, fieldOwner:Bool):HxExpr {
		return switch constant {
			case CInt(text, suffix):
				if (suffix != null)
					throw failure("integer literal suffix `" + suffix + "` is not imported yet");
				final value = Std.parseInt(text);
				if (value == null)
					throw failure("integer literal `" + text + "` is not a valid Int");
				EInt(value);
			case CFloat(text, suffix):
				if (suffix != null)
					throw failure("float literal suffix `" + suffix + "` is not imported yet");
				final value = Std.parseFloat(text);
				if (Math.isNaN(value))
					throw failure("float literal `" + text + "` is not a valid Float");
				EFloat(value);
			case CString(text, kind):
				if (kind == SingleQuotes && text.indexOf("$") >= 0)
					throw failure("single-quoted strings with interpolation are not imported yet");
				EString(text);
			case CRegexp(pattern, options):
				ENew("EReg", [EString(pattern), EString(options)]);
			case CIdent(name):
				switch name {
					case "null": ENull;
					case "true": EBool(true);
					case "false": EBool(false);
					case "this": EThis;
					case "super": ESuper;
					case _: !fieldOwner && isEnumValueName(name) ? EEnumValue(name) : EIdent(name);
				}
		};
	}

	/** Same rule as `HxParser` for a standalone identifier that is not followed by `.`. */
	static function isEnumValueName(name:String):Bool {
		if (name.length == 0 || name.indexOf("_") >= 0)
			return false;
		final first = name.charCodeAt(0);
		if (!(first >= "A".code && first <= "Z".code))
			return false;
		for (index in 0...name.length) {
			final code = name.charCodeAt(index);
			if (code >= "a".code && code <= "z".code)
				return true;
		}
		return false;
	}

	function declaration(variable:Var, owner:Expr):HxExpr {
		if (variable.meta != null && variable.meta.length != 0)
			throw failure("metadata on local variable `" + variable.name + "` is not imported yet");
		final restored = positions.resolve(variable.namePos);
		final declared = restored == null ? position(owner) : restored;
		return HxExprVarDecl.make(variable.name, variable.type == null ? "" : typeText(variable.type), optional(variable.expr), declared,
			variable.isFinal == true, variable.isStatic == true);
	}

	function sourceFunction(kind:Null<FunctionKind>, body:Function, statement:Bool, expression:Expr):HxExpr {
		if (body == null)
			throw failure("a function has no definition");
		if (body.params != null && body.params.length != 0)
			throw failure("type parameters on local functions are not imported yet");
		if (body.expr == null)
			throw failure("a local function has no body");
		final sourceKind = kind == null ? HxSourceFunctionKind.Anonymous : functionKind(kind);
		final placement:HxSourceFunctionPlacement = switch sourceKind {
			case Named(_, _) if (statement): Declaration;
			case _: Value;
		};
		final names = new Array<String>();
		final parameters = new Array<HxLambdaParameter>();
		final defaults = new Array<HxExpr>();
		final arguments:Array<FunctionArg> = body.args == null ? [] : body.args;
		for (argument in arguments) {
			if (argument.meta != null && argument.meta.length != 0)
				throw failure("metadata on parameter `" + argument.name + "` is not imported yet");
			final rest = restElement(argument.type);
			final written = rest != null ? rest : argument.type;
			final hasDefault = argument.value != null;
			// Export marks a defaulted arrow parameter optional, as upstream does; only the default is written.
			final optional = argument.opt == true && !(sourceKind == Arrow && hasDefault);
			names.push(argument.name);
			parameters.push({
				typeHint: written == null ? null : typeText(written),
				isOptional: optional,
				isRest: rest != null,
				hasDefault: hasDefault
			});
			if (hasDefault)
				defaults.push(convert(argument.value, false));
		}
		final facts = new HxSourceFunction({
			kind: sourceKind,
			placement: placement,
			arguments: names,
			signature: new HxLambdaSignature(parameters, body.ret == null ? null : typeText(body.ret))
		});
		return ESourceFunction(facts, convert(body.expr, false), defaults, position(expression));
	}

	// Switches below take non-null typed values: the bootstrap OCaml backend mislowers a switch whose
	// scrutinee has a `Null<T>` static type, so each nullable value is checked first.
	static function functionKind(kind:FunctionKind):HxSourceFunctionKind {
		return switch kind {
			case FAnonymous: Anonymous;
			case FNamed(name, inlined): Named(name, inlined == true);
			case FArrow: Arrow;
		};
	}

	/** `haxe.Rest<T>` on a parameter is the written `...name:T` form. */
	static function restElement(type:Null<ComplexType>):Null<ComplexType>
		return type == null ? null : restElementOf(type);

	static function restElementOf(type:ComplexType):Null<ComplexType> {
		final path = switch type {
			case TPath(value): value;
			case _: return null;
		};
		final pack = path.pack;
		final params = path.params;
		if (path.name != "Rest" || path.sub != null || pack == null || pack.length != 1 || pack[0] != "haxe" || params == null || params.length != 1)
			return null;
		return switch params[0] {
			case TPType(element): element;
			case TPExpr(_): null;
		};
	}

	/**
		The parser's two loop bindings: `name in iterable`, and `key => value in iterable`, which
		the public tree nests as `key => (value in iterable)`. Each level is matched separately;
		the bootstrap OCaml backend does not lower a structure pattern nested in an enum pattern.
	**/
	function sourceFor(iterator:Expr, body:Expr, expression:Expr):HxExpr {
		if (iterator == null)
			throw failure("a for loop has no iterator");
		final shape:ExprDef = iterator.expr;
		switch shape {
			case EBinop(OpIn, binding, iterable):
				return ESourceFor(Value(loopName(binding)), convert(iterable, false), convert(body, false), position(expression));
			case EBinop(OpArrow, key, valueIterator):
				if (valueIterator == null)
					throw failure("a key/value for loop has no value binding");
				final inner:ExprDef = valueIterator.expr;
				switch inner {
					case EBinop(OpIn, value, iterable):
						return ESourceFor(KeyValue(loopName(key), loopName(value)), convert(iterable, false), convert(body, false), position(expression));
					case _:
				}
			case _:
		}
		throw failure("a for loop iterator must be `name in iterable` or `key => value in iterable`");
	}

	static function loopName(binding:Expr):String {
		if (binding == null)
			throw failure("a for loop binding is missing");
		final shape:ExprDef = binding.expr;
		return switch shape {
			case EConst(CIdent(name)): name;
			case _: throw failure("a for loop binding must be an identifier");
		};
	}

	static function binopToken(op:Binop):String {
		return switch op {
			case OpAdd: "+";
			case OpMult: "*";
			case OpDiv: "/";
			case OpSub: "-";
			case OpAssign: "=";
			case OpEq: "==";
			case OpNotEq: "!=";
			case OpGt: ">";
			case OpGte: ">=";
			case OpLt: "<";
			case OpLte: "<=";
			case OpAnd: "&";
			case OpOr: "|";
			case OpXor: "^";
			case OpBoolAnd: "&&";
			case OpBoolOr: "||";
			case OpShl: "<<";
			case OpShr: ">>";
			case OpUShr: ">>>";
			case OpMod: "%";
			case OpAssignOp(inner):
				switch inner {
					case OpAssignOp(_) | OpAssign | OpEq | OpNotEq | OpGt | OpGte | OpLt | OpLte | OpBoolAnd | OpBoolOr | OpInterval | OpArrow | OpIn:
						throw failure("operator " + binopToken(inner) + " has no compound assignment form");
					case _:
						binopToken(inner) + "=";
				}
			case OpInterval: "...";
			case OpArrow: "=>";
			case OpIn: "in";
			case OpNullCoal: "??";
		};
	}

	static function unop(op:Unop):HxUnaryOperator {
		return switch op {
			case OpIncrement: Increment;
			case OpDecrement: Decrement;
			case OpNot: LogicalNot;
			case OpNeg: Negate;
			case OpNegBits: BitwiseNot;
			case OpSpread: throw failure("spread arguments are not imported yet");
		};
	}

	/** Print a type in the parser's stored annotation form (no spaces). */
	public static function typeText(type:ComplexType):String {
		if (type == null)
			throw failure("a required type is missing");
		return switch type {
			case TPath(path):
				typePathText(path);
			case TFunction(arguments, result):
				final printed = [for (argument in arguments) typeText(argument)];
				final simple = arguments.length == 1 && switch arguments[0] {
					case TFunction(_, _) | TNamed(_, _) | TOptional(_): false;
					case _: true;
				};
				final resultText = switch result {
					case TFunction(_, _): "(" + typeText(result) + ")";
					case _: typeText(result);
				};
				(simple ? printed[0] : "(" + printed.join(",") + ")") + "->" + resultText;
			case TParent(inner):
				"(" + typeText(inner) + ")";
			case TOptional(inner):
				"?" + typeText(inner);
			case TNamed(name, inner):
				name + ":" + typeText(inner);
			case TIntersection(members):
				[for (member in members) typeText(member)].join("&");
			case TAnonymous(fields):
				"{" + [for (field in fields) anonymousField(field)].join(",") + "}";
			case TExtend(_, _):
				throw failure("structure extension types are not imported yet");
		};
	}

	static function anonymousField(field:Field):String {
		if (field.access != null && field.access.length != 0)
			throw failure("access modifiers on structure field `" + field.name + "` are not imported yet");
		var optional = false;
		if (field.meta != null)
			for (entry in field.meta) {
				if (entry.name == ":optional" && (entry.params == null || entry.params.length == 0))
					optional = true;
				else
					throw failure("metadata on structure field `" + field.name + "` is not imported yet");
			}
		return switch field.kind {
			case FVar(type, null) if (type != null):
				(optional ? "?" : "") + field.name + ":" + typeText(type);
			case _:
				throw failure("structure field `" + field.name + "` is not a plain typed variable");
		};
	}

	public static function typePathText(path:TypePath):String {
		if (path == null || path.name == null || path.name.length == 0)
			throw failure("a type path has no name");
		final segments = path.pack == null ? [] : path.pack.copy();
		segments.push(path.name);
		if (path.sub != null)
			segments.push(path.sub);
		final parameters = path.params == null ? [] : path.params;
		if (parameters.length == 0)
			return segments.join(".");
		return segments.join(".") + "<" + [
			for (parameter in parameters)
				switch parameter {
					case TPType(type):
						typeText(type);
					case TPExpr(_):
						throw failure("expression type parameters are not imported yet");
				}
		].join(",") + ">";
	}

	static function failure(message:String):String
		return "macro syntax import: " + message;
}
