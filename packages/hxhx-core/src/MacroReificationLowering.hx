import haxe.macro.Expr;

/**
	One authored splice inside a macro quotation, kept as ordinary syntax until the lowered
	expression is typed in the quote's own scope.
**/
enum MacroReificationHole {
	/** `$e{e}`, `${e}`, or a bare `$e`: an `Expr` value used in place. */
	ExpressionHole(payload:HxExpr);

	/** `$i{name}`: a `String` that becomes an identifier constant. */
	IdentifierHole(payload:HxExpr);

	/** `$b{list}`: an `Array<Expr>` that becomes a block. */
	BlockHole(payload:HxExpr);

	/** `$a{list}`: an `Array<Expr>` spliced as a sole argument list or array literal, else an `EArrayDecl`. */
	ArrayHole(payload:HxExpr);

	/** `$v{value}`: a run-time value turned into a constant by its static type. */
	ValueHole(payload:HxExpr);

	/** `new $tp(...)`: a `TypePath` value. */
	TypePathHole(payload:HxExpr);

	/** `@:pos(p) e`: the `Position` every node of `e` receives. */
	PositionHole(payload:HxExpr);
}

/**
	Lower a macro quotation (`macro ...`, `macro :Type`) to ordinary syntax that builds the
	`haxe.macro.Expr` value, before the quote is typed.

	Why
	- Upstream Haxe treats a quotation as sugar: the quoted source becomes an expression that
	  constructs the public `haxe.macro.Expr` tree, splices (`$v{}`, `$i{}`, ...) become holes
	  filled by ordinary code, and the result is typed like any other expression. hxhx's parser
	  keeps the quote as `EMacroExpr`/`EMacroType` with the parser's splice markers inside. Before
	  this lowering the Stage3 emitter rejected every quote, so a project macro plugin could not
	  use reification.
	- The lowering happens once, in the typer, for every target: the typed program contains only
	  enum constructions, anonymous objects, literals, and the splice payloads typed in the
	  macro's own scope. Backends never see a quote.

	What
	- `lowerExpression` handles `macro e` (with an optional `untyped` wrapper). The quoted syntax
	  is exported to an `Expr` value with `MacroSyntaxExport`, so a quotation and a macro call
	  argument share one syntax mapping; a hook turns each splice marker into a placeholder.
	  `MacroReificationSyntax` then writes the constructing syntax and puts each payload back.
	- `lowerType` handles `macro :Type` through the shared type grammar (`HxTypedefParser`) and
	  `HxMacroTypeSyntax`, giving a `ComplexType` construction.
	- `$v{}` is decided by the payload's static type, supplied by the caller's `valueType` probe:
	  Int, Float, Bool, String, and `Null<T>` or `Array<T>` of those four (through
	  `hxhxmacrohost.MacroReificationValues`, present on every plugin build's classpath, which
	  reads the payload once and decides null at run time). Other types are a compile error, as upstream rejects unsupported values
	  at macro run time.

	Positions
	- Every node receives a zero-width position in the macro's source file: a quoted node that
	  owns a parser position gets its own start, every other node the nearest enclosing one, and
	  the quote as a whole `anchor` (the statement that contains it). This is the same contract
	  as macro call arguments (`MacroSyntaxPositions`); exact ranges are owned by
	  `haxe_ocaml-9sj5p.2`. `@:pos(p)` replaces every position inside with `p`, as upstream does.

	Not lowered yet (explicit errors): `$p{}`, metadata other than `@:pos` and `@:privateAccess`,
	the syntax `MacroSyntaxExport` cannot export (switch), and `macro class` in a macro module;
	outside one, `macro class` keeps the parser's placeholder object for bring-up code.
**/
class MacroReificationLowering {
	/** Prefix of the identifier the exporter writes where a splice was; the index follows. */
	public static inline final HOLE_PREFIX = "__hxhx_macro_hole:";

	/** The parser's marker for `o.$name`; the name follows. */
	public static inline final FIELD_SPLICE_PREFIX = "__hxhx_macro_field_splice:";

	static inline final TYPE_PATH_SPLICE_PREFIX = "__hxhx_macro_type_path_splice:";
	static inline final MARKER_PREFIX = "__hxhx_macro_";

	final file:String;
	final anchor:HxPos;
	final root:Position;
	final positions:MacroSyntaxPositions;
	final holes:Array<MacroReificationHole>;
	final valueType:HxExpr->TyType;

	final rooted:Bool;

	function new(file:String, anchor:HxPos, valueType:HxExpr->TyType, rooted:Bool) {
		this.rooted = rooted;
		if (file == null || file.length == 0)
			throw failure("the macro's source file is unknown");
		this.file = file;
		this.anchor = anchor;
		this.valueType = valueType;
		positions = new MacroSyntaxPositions(file);
		root = MacroSyntaxPositions.isKnown(anchor) ? positions.export(anchor) : {file: file, min: 0, max: 0};
		holes = [];
	}

	/**
		Syntax that builds the `Expr` of `macro <quoted>`.

		`wrappers` is the parser's list of quote modifiers (`untyped`, or `class` for a
		`macro class` placeholder). `anchor` is the position of the statement that contains the
		quote, in `file`. `valueType` gives the static type of a `$v{}` payload in the quote's
		scope. `inMacroContext` is true when the module is compiled as macro code (a plugin
		build), where a placeholder class definition is refused.

		`rooted` writes the generated type paths as rooted paths (`HxRootedPath`) so user names
		cannot capture them. The typer passes false only when it has no module loader: a module
		typed without a classpath (isolated unit typing, the legacy `CompilerDriver`) cannot
		resolve `haxe.macro.Expr` at all, and there the plain chains keep the earlier best-effort
		shape instead of failing the rooted-owner check.
	**/
	public static function lowerExpression(quoted:HxExpr, wrappers:Null<Array<String>>, file:String, anchor:HxPos, valueType:HxExpr->TyType,
			inMacroContext:Bool, rooted:Bool = true):HxExpr {
		final lowering = new MacroReificationLowering(file, anchor, valueType, rooted);
		var expression = quoted;
		if (wrappers != null) {
			if (wrappers.indexOf("class") >= 0) {
				// The parser keeps a placeholder definition for Stage3 bring-up code; a macro
				// module (plugin build) would hand a macro an empty class, so it is refused.
				if (inMacroContext)
					throw failure("`macro class` quotations are not lowered yet (haxe_ocaml-9sj5p.5.4); a macro module cannot use one");
				return quoted;
			}
			var index = wrappers.length;
			while (index > 0) {
				index--;
				if (wrappers[index] == "untyped")
					expression = EUntyped(expression);
			}
		}
		final exported = new MacroSyntaxExport(lowering.positions, lowering.splice).quotation(expression, lowering.root);
		return lowering.syntax().expression(exported);
	}

	/** Syntax that builds the `ComplexType` of `macro :<typeText>`. */
	public static function lowerType(typeText:String, file:String, anchor:HxPos, rooted:Bool = true):HxExpr {
		final lowering = new MacroReificationLowering(file, anchor, _ -> TyType.unknown(), rooted);
		final text = typeText == null ? "" : StringTools.trim(typeText);
		if (text.length == 0)
			throw failure("`macro :` requires a type");
		final parsed = try {
			HxTypedefParser.parseTypeHint(text);
		} catch (error:HxParseError) {
			throw failure("quoted type `" + text + "` could not be read: " + error.message);
		}
		final converted = HxMacroTypeSyntax.convert(parsed, lowering.root, _ -> throw failure("metadata inside a quoted type is not lowered yet"));
		return lowering.syntax().complexType(converted);
	}

	function syntax():MacroReificationSyntax
		return new MacroReificationSyntax(holes, value, rooted);

	function hole(kind:MacroReificationHole):ExprDef {
		holes.push(kind);
		return EConst(CIdent(HOLE_PREFIX + (holes.length - 1)));
	}

	function holeName(kind:MacroReificationHole):String {
		holes.push(kind);
		return HOLE_PREFIX + (holes.length - 1);
	}

	/** The exporter's hook: the parser's splice and quote markers become placeholders or public syntax. */
	function splice(expression:HxExpr, child:HxExpr->Expr):Null<ExprDef> {
		return switch expression {
			case ECall(EIdent(marker), arguments) if (StringTools.startsWith(marker, MARKER_PREFIX)):
				switch marker {
					case "__hxhx_macro_expr_splice": hole(ExpressionHole(payload(marker, arguments)));
					case "__hxhx_macro_ident_splice": hole(IdentifierHole(payload(marker, arguments)));
					case "__hxhx_macro_block_splice": hole(BlockHole(payload(marker, arguments)));
					case "__hxhx_macro_a_splice": hole(ArrayHole(payload(marker, arguments)));
					case "__hxhx_macro_v_splice": hole(ValueHole(payload(marker, arguments)));
					case "__hxhx_macro_p_splice": throw failure("`$p{}` is not lowered yet");
					case "__hxhx_macro_if":
						if (arguments.length != 3)
							throw failure("a quoted `if` requires a condition and a branch");
						final whenFalse = arguments[2].match(EIdent("__hxhx_macro_missing_else")) ? null : child(arguments[2]);
						EIf(child(arguments[0]), child(arguments[1]), whenFalse);
					case _: throw failure("unsupported splice `" + marker + "`");
				}
			case ECall(EIdent("__hxhx_expr_meta"), [EString(name), EString(argumentText), inner]):
				metadata(name, argumentText, inner, child);
			case EIdent("__hxhx_macro_missing_else"):
				throw failure("a quoted `if` branch is missing");
			case ENew(typePath, arguments) if (StringTools.startsWith(typePath, TYPE_PATH_SPLICE_PREFIX)):
				final name = holeName(TypePathHole(EIdent(typePath.substr(TYPE_PATH_SPLICE_PREFIX.length))));
				ENew({
					pack: [],
					name: name,
					params: [],
					sub: null
				}, [for (argument in arguments) child(argument)]);
			case _:
				null;
		};
	}

	static function payload(marker:String, arguments:Array<HxExpr>):HxExpr {
		if (arguments.length != 1)
			throw failure("splice `" + marker + "` requires exactly one payload");
		return arguments[0];
	}

	/** `@:pos(p) e` is the only expression metadata with a lowering; others wait on a parser form that keeps their spelling. */
	function metadata(name:String, argumentText:String, inner:HxExpr, child:HxExpr->Expr):ExprDef {
		if (name != "pos")
			throw failure("metadata `@" + name + "` inside a quotation is not lowered yet; only @:pos and @:privateAccess are");
		final text = StringTools.trim(argumentText);
		if (text.length == 0)
			throw failure("@:pos requires a position expression");
		final position = try {
			HxParser.parseCompleteExprText(text);
		} catch (error:HxParseError) {
			throw failure("@:pos argument `" + text + "` could not be read: " + error.message);
		}
		final marker:Expr = {expr: hole(PositionHole(position)), pos: root};
		return EMeta({name: ":pos", params: [marker], pos: root}, child(inner));
	}

	// --- `$v{}` --------------------------------------------------------------------------------

	function constantExpr(constructor:String, arguments:Array<HxExpr>, at:HxExpr):HxExpr {
		final constant = ECall(syntax().enumPath("Constant", constructor), arguments);
		return EAnon(["expr", "pos"], [ECall(syntax().enumPath("ExprDef", "EConst"), [constant]), at]);
	}

	/** The constant for a `$v{payload}` whose static type is `type`; `at` is the position syntax. */
	function value(payload:HxExpr, at:HxExpr):HxExpr
		return valueOfType(payload, valueType(payload), at);

	function valueOfType(payload:HxExpr, type:TyType, at:HxExpr):HxExpr {
		if (type == null || type.isUnknown())
			throw failure("`$v{}` requires a payload whose type is known here");
		if (type.isNullLiteral())
			return constantExpr("CIdent", [EString("null")], at);
		if (type.isNullWrapped()) {
			// Upstream decides at macro run time; the helper reads the payload once.
			final inner = type.unwrapNull();
			final helper = inner.isPrimitive() ? switch inner.getDisplay() {
				case "Int": "nullableInt";
				case "Float": "nullableFloat";
				case "Bool": "nullableBool";
				case "String": "nullableString";
				case _: null;
			} : null;
			if (helper == null)
				throw failure("`$v{}` supports Null of Int, Float, Bool, or String; this payload has type " + type.getDisplay());
			return ECall(valuesHelper(helper), [payload, at]);
		}
		final stringOf = ECall(HxRootedPath.expression("Std.string", rooted), [payload]);
		if (type.isPrimitive()) {
			switch type.getDisplay() {
				case "Int":
					return constantExpr("CInt", [stringOf, ENull], at);
				case "Float":
					return constantExpr("CFloat", [stringOf, ENull], at);
				case "Bool":
					return constantExpr("CIdent", [ETernary(payload, EString("true"), EString("false"))], at);
				case "String":
					return constantExpr("CString", [payload, syntax().enumPath("StringLiteralKind", "DoubleQuotes")], at);
				case _:
			}
		}
		final elements = arrayElementType(type);
		if (elements != null) {
			// The loop lives in `hxhxmacrohost.MacroReificationValues`: the native emitter does not
			// yet accept a loop, closure, or block value as an enum constructor argument.
			final helper = elements.isPrimitive() ? switch elements.getDisplay() {
				case "Int": "ints";
				case "Float": "floats";
				case "Bool": "bools";
				case "String": "strings";
				case _: null;
			} : null;
			if (helper == null)
				throw failure("`$v{}` supports arrays of Int, Float, Bool, or String; this payload has type " + type.getDisplay());
			return ECall(valuesHelper(helper), [payload, at]);
		}
		throw failure("`$v{}` supports Int, Float, Bool, String, Null of those, and arrays of those; this payload has type " + type.getDisplay());
	}

	function valuesHelper(name:String):HxExpr
		return HxRootedPath.expression("hxhxmacrohost.MacroReificationValues." + name, rooted);

	static function arrayElementType(type:TyType):Null<TyType> {
		final display = type.getDisplay();
		if (display != "Array" && !StringTools.startsWith(display, "Array<"))
			return null;
		final arguments = type.getTypeArguments();
		return arguments.length == 1 ? arguments[0] : null;
	}

	static function failure(message:String):String
		return "macro reification: " + message;
}
