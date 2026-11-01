import haxe.macro.Expr;
import MacroReificationLowering.MacroReificationHole;

/**
	Write parser syntax that builds a given `haxe.macro.Expr` value when it runs.

	Why
	- A macro quotation (`macro 1 + $v{n}`) is sugar for an expression that constructs the public
	  `haxe.macro.Expr` tree at run time. `MacroReificationLowering` first exports the quoted
	  syntax to an `Expr` value (with placeholder nodes where splices were written) and then asks
	  this class for ordinary syntax that rebuilds that value: fully qualified enum constructors,
	  anonymous objects for the typedef records, string and integer literals, and the authored
	  splice payloads in the placeholders' places.

	What
	- `expression` and `complexType` return `HxExpr` syntax; nothing here is target-specific, the
	  typer and every backend treat the result as ordinary code.
	- Enum constructors are written as `haxe.macro.Expr.<Enum>.<Constructor>(...)`, so the lowered
	  code needs no import in the macro's module.
	- Records are written with every field of the 4.3.7 typedef, absent optional fields as `null`,
	  the same shape `hxhxmacrohost.MacroSyntaxWire` builds in a plugin.
	- Positions become `cast({file: .., min: .., max: ..}, haxe.macro.Expr.Position)`: hxhx
	  compiles `haxe.macro.Expr` in the macro context in every request, where `Position` is an
	  opaque abstract, and this record is what `MacroSyntaxWire` and `Context.getPosInfos` read.
	  Inside `@:pos(p)` every position is the authored expression `p` instead.

	Splice placeholders (see `MacroReificationLowering`):
	- `EConst(CIdent("<hole>"))` stands for an expression, identifier, block, array, or value
	  splice; `ECall(f, [<array hole>])` and `EArrayDecl([<array hole>])` splice the payload list
	  itself, as upstream does for a sole `$a{}`;
	- a field name or a `TypePath.name` that is a placeholder stands for `o.$name` / `new $tp()`;
	- `EMeta({name: ":pos", params: [<position hole>]}, e)` applies `@:pos(p)` to `e`.
**/
class MacroReificationSyntax {
	static inline final MODULE = "haxe.macro.Expr";

	final holes:Array<MacroReificationHole>;
	final valueSplice:(payload:HxExpr, position:HxExpr) -> HxExpr;
	var positionOverride:Null<HxExpr>;

	/** `valueSplice` builds the `$v{}` constant for a typed payload; the lowering owns that policy. */
	public function new(holes:Array<MacroReificationHole>, valueSplice:(payload:HxExpr, position:HxExpr) -> HxExpr) {
		this.holes = holes;
		this.valueSplice = valueSplice;
		positionOverride = null;
	}

	public function expression(value:Expr):HxExpr
		return expr(value);

	public function complexType(value:ComplexType):HxExpr
		return type(value);

	// --- syntax helpers -------------------------------------------------------------------------

	static function qualified(path:String):HxExpr {
		final parts = path.split(".");
		var out:HxExpr = EIdent(parts[0]);
		for (index in 1...parts.length)
			out = EField(out, parts[index]);
		return out;
	}

	/** The fully qualified constructor `haxe.macro.Expr.<owner>.<name>` as syntax. */
	public static function enumPath(owner:String, name:String):HxExpr
		return qualified(MODULE + "." + owner + "." + name);

	/** `haxe.macro.Expr.<owner>.<name>(args)`, or the bare constructor value when it has no payload. */
	static function ctor(owner:String, name:String, args:Array<HxExpr>):HxExpr {
		final path = enumPath(owner, name);
		return args.length == 0 ? path : ECall(path, args);
	}

	static function record(names:Array<String>, values:Array<HxExpr>):HxExpr
		return EAnon(names, values);

	static function str(value:String):HxExpr
		return EString(value);

	static function bool(value:Bool):HxExpr
		return EBool(value);

	static function list(values:Array<HxExpr>):HxExpr
		return EArrayDecl(values);

	static function optionalString(value:Null<String>):HxExpr
		return value == null ? ENull : EString(value);

	static function optionalBool(value:Null<Bool>):HxExpr
		return value == null ? ENull : EBool(value);

	// --- splice placeholders --------------------------------------------------------------------

	function holeOf(name:Null<String>):Null<MacroReificationHole> {
		if (name == null || !StringTools.startsWith(name, MacroReificationLowering.HOLE_PREFIX))
			return null;
		final index = Std.parseInt(name.substr(MacroReificationLowering.HOLE_PREFIX.length));
		if (index == null || index < 0 || index >= holes.length)
			throw "macro reification: unknown splice placeholder `" + name + "`";
		return holes[index];
	}

	static function constantHoleName(definition:ExprDef):Null<String> {
		return switch definition {
			case EConst(CIdent(name)) if (StringTools.startsWith(name, MacroReificationLowering.HOLE_PREFIX)): name;
			case _: null;
		};
	}

	function arrayHolePayload(values:Array<Expr>):Null<HxExpr> {
		if (values.length != 1)
			return null;
		return switch holeOf(constantHoleName(values[0].expr)) {
			case ArrayHole(payload): payload;
			case _: null;
		};
	}

	// --- positions ------------------------------------------------------------------------------

	function position(value:Position):HxExpr {
		if (positionOverride != null)
			return positionOverride;
		final facts:hxhxmacrohost.MacroSyntaxWire.MacroSyntaxWirePosition = cast value;
		final fields = record(["file", "min", "max"], [str(facts.file), EInt(facts.min), EInt(facts.max)]);
		// A hinted cast names the destination without an inference variable; the backends emit the record itself.
		return ECast(fields, MODULE + ".Position");
	}

	function optionalPosition(value:Null<Position>):HxExpr
		return value == null ? ENull : position(value);

	// --- expressions ----------------------------------------------------------------------------

	function expr(value:Expr):HxExpr {
		final hole = holeOf(constantHoleName(value.expr));
		if (hole != null) {
			final at = position(value.pos);
			return switch hole {
				case ExpressionHole(payload): payload;
				case IdentifierHole(payload): exprRecord(ctor("ExprDef", "EConst", [ctor("Constant", "CIdent", [payload])]), at);
				case BlockHole(payload): exprRecord(ctor("ExprDef", "EBlock", [payload]), at);
				case ArrayHole(payload): exprRecord(ctor("ExprDef", "EArrayDecl", [payload]), at);
				case ValueHole(payload): valueSplice(payload, at);
				case TypePathHole(_) | FieldNameHole(_) | PositionHole(_):
					throw "macro reification: a type path, field name, or position splice was written in expression position";
			};
		}
		switch value.expr {
			case EMeta(entry, inner) if (entry.name == ":pos" && entry.params != null && entry.params.length == 1):
				switch holeOf(constantHoleName(entry.params[0].expr)) {
					case PositionHole(payload):
						final previous = positionOverride;
						positionOverride = payload;
						final rewritten = expr(inner);
						positionOverride = previous;
						return rewritten;
					case null:
					case _:
						throw "macro reification: @:pos requires a position expression";
				}
			case _:
		}
		return exprRecord(exprDef(value.expr), position(value.pos));
	}

	static function exprRecord(definition:HxExpr, position:HxExpr):HxExpr
		return record(["expr", "pos"], [definition, position]);

	function optionalExpr(value:Null<Expr>):HxExpr
		return value == null ? ENull : expr(value);

	/** An argument or element list; a sole `$a{}` splice contributes the payload array itself. */
	function exprs(values:Array<Expr>):HxExpr {
		final spliced = arrayHolePayload(values);
		return spliced != null ? spliced : list([for (value in values) expr(value)]);
	}

	function def(name:String, args:Array<HxExpr>):HxExpr
		return ctor("ExprDef", name, args);

	function exprDef(value:ExprDef):HxExpr {
		return switch value {
			case EConst(c): def("EConst", [constant(c)]);
			case EArray(e1, e2): def("EArray", [expr(e1), expr(e2)]);
			case EBinop(op, e1, e2): def("EBinop", [binop(op), expr(e1), expr(e2)]);
			case EField(e, field, kind): def("EField", [expr(e), fieldName(field), fieldKind(kind)]);
			case EParenthesis(e): def("EParenthesis", [expr(e)]);
			case EObjectDecl(fields): def("EObjectDecl", [list([for (field in fields) objectField(field)])]);
			case EArrayDecl(values): def("EArrayDecl", [exprs(values)]);
			case ECall(e, params): def("ECall", [expr(e), exprs(params)]);
			case ENew(t, params): def("ENew", [typePath(t), exprs(params)]);
			case EUnop(op, postFix, e): def("EUnop", [unop(op), bool(postFix), expr(e)]);
			case EVars(vars): def("EVars", [list([for (v in vars) variable(v)])]);
			case EFunction(kind, f): def("EFunction", [functionKind(kind), func(f)]);
			case EBlock(exprList): def("EBlock", [list([for (e in exprList) expr(e)])]);
			case EFor(it, e): def("EFor", [expr(it), expr(e)]);
			case EIf(econd, eif, eelse): def("EIf", [expr(econd), expr(eif), optionalExpr(eelse)]);
			case EWhile(econd, e, normalWhile): def("EWhile", [expr(econd), expr(e), bool(normalWhile)]);
			case ESwitch(e, cases, edef): def("ESwitch", [expr(e), list([for (c in cases) switchCase(c)]), optionalExpr(edef)]);
			case ETry(e, catches): def("ETry", [expr(e), list([for (c in catches) catchClause(c)])]);
			case EReturn(e): def("EReturn", [optionalExpr(e)]);
			case EBreak: def("EBreak", []);
			case EContinue: def("EContinue", []);
			case EUntyped(e): def("EUntyped", [expr(e)]);
			case EThrow(e): def("EThrow", [expr(e)]);
			case ECast(e, t): def("ECast", [expr(e), optionalType(t)]);
			case ETernary(econd, eif, eelse): def("ETernary", [expr(econd), expr(eif), expr(eelse)]);
			case ECheckType(e, t): def("ECheckType", [expr(e), type(t)]);
			case EMeta(s, e): def("EMeta", [metadataEntry(s), expr(e)]);
			case EIs(e, t): def("EIs", [expr(e), type(t)]);
			case EDisplay(_, _): throw "macro reification: display syntax cannot be quoted";
		};
	}

	/** `o.$name` carries the authored name expression; any other field is its literal text. */
	function fieldName(field:String):HxExpr {
		if (StringTools.startsWith(field, MacroReificationLowering.FIELD_SPLICE_PREFIX))
			return EIdent(field.substr(MacroReificationLowering.FIELD_SPLICE_PREFIX.length));
		return str(field);
	}

	function constant(value:Constant):HxExpr {
		return switch value {
			case CInt(v, s): ctor("Constant", "CInt", [str(v), optionalString(s)]);
			case CFloat(f, s): ctor("Constant", "CFloat", [str(f), optionalString(s)]);
			case CString(s, kind): ctor("Constant", "CString", [str(s), kind == null ? ENull : stringKind(kind)]);
			case CIdent(s): ctor("Constant", "CIdent", [str(s)]);
			case CRegexp(r, opt): ctor("Constant", "CRegexp", [str(r), str(opt)]);
		};
	}

	function stringKind(value:StringLiteralKind):HxExpr {
		return switch value {
			case DoubleQuotes: ctor("StringLiteralKind", "DoubleQuotes", []);
			case SingleQuotes: ctor("StringLiteralKind", "SingleQuotes", []);
		};
	}

	function fieldKind(value:Null<EFieldKind>):HxExpr {
		return switch value {
			case null: ENull;
			case Normal: ctor("EFieldKind", "Normal", []);
			case Safe: ctor("EFieldKind", "Safe", []);
		};
	}

	function binop(value:Binop):HxExpr
		return HxMacroBinaryOperator.renderOperation(value, (name, args) -> ctor("Binop", name, args));

	function unop(value:Unop):HxExpr {
		final name = switch value {
			case OpIncrement: "OpIncrement";
			case OpDecrement: "OpDecrement";
			case OpNot: "OpNot";
			case OpNeg: "OpNeg";
			case OpNegBits: "OpNegBits";
			case OpSpread: "OpSpread";
		};
		return ctor("Unop", name, []);
	}

	function quoteStatus(value:Null<QuoteStatus>):HxExpr {
		return switch value {
			case null: ENull;
			case Unquoted: ctor("QuoteStatus", "Unquoted", []);
			case Quoted: ctor("QuoteStatus", "Quoted", []);
		};
	}

	function objectField(value:ObjectField):HxExpr
		return record(["field", "expr", "quotes"], [str(value.field), expr(value.expr), quoteStatus(value.quotes)]);

	function variable(value:Var):HxExpr {
		return record(["name", "namePos", "type", "expr", "isFinal", "isStatic", "meta"], [
			str(value.name),
			optionalPosition(value.namePos),
			optionalType(value.type),
			optionalExpr(value.expr),
			optionalBool(value.isFinal),
			optionalBool(value.isStatic),
			optionalMetadata(value.meta)
		]);
	}

	function switchCase(value:Case):HxExpr
		return record(["values", "guard", "expr"], [
			list([for (v in value.values) expr(v)]),
			optionalExpr(value.guard),
			optionalExpr(value.expr)
		]);

	function catchClause(value:Catch):HxExpr
		return record(["name", "type", "expr"], [str(value.name), optionalType(value.type), expr(value.expr)]);

	function functionKind(value:Null<FunctionKind>):HxExpr {
		return switch value {
			case null: ENull;
			case FAnonymous: ctor("FunctionKind", "FAnonymous", []);
			case FArrow: ctor("FunctionKind", "FArrow", []);
			case FNamed(name, inlined): ctor("FunctionKind", "FNamed", [str(name), optionalBool(inlined)]);
		};
	}

	function func(value:Function):HxExpr {
		return record(["args", "ret", "expr", "params"], [
			list([for (arg in value.args) functionArg(arg)]),
			optionalType(value.ret),
			optionalExpr(value.expr),
			value.params == null ? ENull : list([for (p in value.params) typeParamDecl(p)])
		]);
	}

	function functionArg(value:FunctionArg):HxExpr {
		return record(["name", "opt", "type", "value", "meta"], [
			str(value.name),
			optionalBool(value.opt),
			optionalType(value.type),
			optionalExpr(value.value),
			optionalMetadata(value.meta)
		]);
	}

	function metadataEntry(value:MetadataEntry):HxExpr {
		return record(["name", "params", "pos"], [
			str(value.name),
			value.params == null ? ENull : list([for (p in value.params) expr(p)]),
			position(value.pos)
		]);
	}

	function optionalMetadata(value:Null<Metadata>):HxExpr
		return value == null ? ENull : list([for (entry in value) metadataEntry(entry)]);

	function typeParamDecl(value:TypeParamDecl):HxExpr {
		return record(["name", "constraints", "defaultType", "params", "meta"], [
			str(value.name),
			value.constraints == null ? ENull : list([for (c in value.constraints) type(c)]),
			optionalType(value.defaultType),
			value.params == null ? ENull : list([for (p in value.params) typeParamDecl(p)]),
			optionalMetadata(value.meta)
		]);
	}

	// --- types ----------------------------------------------------------------------------------

	function optionalType(value:Null<ComplexType>):HxExpr
		return value == null ? ENull : type(value);

	function type(value:ComplexType):HxExpr {
		return switch value {
			case TPath(p): ctor("ComplexType", "TPath", [typePath(p)]);
			case TFunction(args, ret): ctor("ComplexType", "TFunction", [list([for (a in args) type(a)]), type(ret)]);
			case TAnonymous(fields): ctor("ComplexType", "TAnonymous", [list([for (f in fields) field(f)])]);
			case TParent(t): ctor("ComplexType", "TParent", [type(t)]);
			case TExtend(p, fields): ctor("ComplexType", "TExtend", [list([for (tp in p) typePath(tp)]), list([for (f in fields) field(f)])]);
			case TOptional(t): ctor("ComplexType", "TOptional", [type(t)]);
			case TNamed(n, t): ctor("ComplexType", "TNamed", [str(n), type(t)]);
			case TIntersection(tl): ctor("ComplexType", "TIntersection", [list([for (t in tl) type(t)])]);
		};
	}

	/** `new $tp()` names its placeholder in `TypePath.name`; the authored `tp` expression replaces the record. */
	function typePath(value:TypePath):HxExpr {
		switch holeOf(value.name) {
			case TypePathHole(payload):
				return payload;
			case null:
			case _:
				throw "macro reification: only a `TypePath` value can be spliced into `new`";
		}
		return record(["pack", "name", "params", "sub"], [
			list([for (p in value.pack) str(p)]),
			str(value.name),
			value.params == null ? ENull : list([for (p in value.params) typeParam(p)]),
			optionalString(value.sub)
		]);
	}

	function typeParam(value:TypeParam):HxExpr {
		return switch value {
			case TPType(t): ctor("TypeParam", "TPType", [type(t)]);
			case TPExpr(e): ctor("TypeParam", "TPExpr", [expr(e)]);
		};
	}

	function field(value:Field):HxExpr {
		return record(["name", "doc", "access", "kind", "pos", "meta"], [
			str(value.name),
			optionalString(value.doc),
			value.access == null ? ENull : list([for (a in value.access) access(a)]),
			fieldType(value.kind),
			position(value.pos),
			optionalMetadata(value.meta)
		]);
	}

	function access(value:Access):HxExpr {
		final name = switch value {
			case APublic: "APublic";
			case APrivate: "APrivate";
			case AStatic: "AStatic";
			case AOverride: "AOverride";
			case ADynamic: "ADynamic";
			case AInline: "AInline";
			case AMacro: "AMacro";
			case AFinal: "AFinal";
			case AExtern: "AExtern";
			case AAbstract: "AAbstract";
			case AOverload: "AOverload";
		};
		return ctor("Access", name, []);
	}

	function fieldType(value:FieldType):HxExpr {
		return switch value {
			case FVar(t, e): ctor("FieldType", "FVar", [optionalType(t), optionalExpr(e)]);
			case FFun(f): ctor("FieldType", "FFun", [func(f)]);
			case FProp(get, set, t, e): ctor("FieldType", "FProp", [str(get), str(set), optionalType(t), optionalExpr(e)]);
		};
	}
}
