import haxe.macro.Expr;
import hxhxmacrohost.MacroSyntaxWire;

/**
	A project macro receives authored syntax as `haxe.macro.Expr` and its result becomes parser
	syntax again. This test proves that round trip without running a macro:

	1. parse a real fixture call and export its argument (`MacroSyntaxExport`),
	2. send it through the plugin payload (`MacroSyntaxWire`) in both directions,
	3. import the identity result (`MacroSyntaxImport`),
	4. compare the imported syntax with the parsed argument using the parser's exact body
	   fingerprint, which covers every node, written annotation, and position.

	Fixtures: the nested-return function of `test/fixtures/project-macro-identity` and the loop of
	`test/fixtures/expression_macro_while`. It also checks the public shape the identity macro
	inspects, the documented position contract, and explicit rejection of unsupported shapes and
	malformed payloads.
**/
class M14MacroSyntaxRoundTripTest {
	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function failureOf(action:Void->Void):String {
		try {
			action();
		} catch (error:String) {
			return error;
		}
		return "";
	}

	static function requireFailure(label:String, prefix:String, fragment:String, action:Void->Void):Void {
		final message = failureOf(action);
		require(StringTools.startsWith(message, prefix) && message.indexOf(fragment) >= 0,
			label
			+ ": expected a failure starting with `"
			+ prefix
			+ "` and containing `"
			+ fragment
			+ "`, got `"
			+ message
			+ "`");
	}

	static function parse(file:String):HxModuleDecl
		return ParserStage.parse(sys.io.File.getContent(file), file).getDecl();

	/** The single argument of the first call to `owner.method` in the main class's `main`. */
	static function macroArgument(file:String, owner:String, method:String):HxExpr {
		final found = new Array<HxExpr>();
		function visit(expression:Null<HxExpr>):Void {
			switch expression {
				case ECall(EField(EIdent(name), field), arguments) if (name == owner && field == method):
					found.push(arguments[0]);
				case ECall(callee, arguments):
					visit(callee);
					for (argument in arguments)
						visit(argument);
				case _:
			}
		}
		for (functionDecl in HxClassDecl.getFunctions(HxModuleDecl.getMainClass(parse(file))))
			for (statement in HxFunctionDecl.getBody(functionDecl))
				switch statement {
					case SVar(_, _, initializer, _, _):
						visit(initializer);
					case SExpr(expression, _):
						visit(expression);
					case _:
				}
		require(found.length == 1, file + ": expected one " + owner + "." + method + " call");
		return found[0];
	}

	/** Export, transport, decode, re-encode, and import one argument; return the imported syntax. */
	static function roundTrip(file:String, argument:HxExpr):{exported:Expr, imported:HxExpr} {
		final positions = new MacroSyntaxPositions(file);
		final exported = new MacroSyntaxExport(positions).argument(argument, 0);
		final payload = MacroSyntaxWire.encodeArguments([exported]);
		final decoded = MacroSyntaxWire.decodeArguments(payload);
		require(decoded.length == 1, file + ": payload changed the argument count");
		require(MacroSyntaxWire.encodeArguments(decoded) == payload, file + ": payload is not stable across a decode");
		final response = MacroSyntaxWire.encodeResult(decoded[0]);
		require(!MacroSyntaxWire.isFailure(response), file + ": a result payload was read as a failure");
		final returned = MacroSyntaxWire.decodeResult(response);
		final imported = new MacroSyntaxImport(positions).result(returned);
		require(TypedBodyFingerprint.exactExpression(imported) == TypedBodyFingerprint.exactExpression(argument),
			file
			+ ": identity round trip changed the syntax:\n  before "
			+ TypedBodyFingerprint.exactExpression(argument)
			+ "\n  after  "
			+ TypedBodyFingerprint.exactExpression(imported));
		return {exported: exported, imported: imported};
	}

	static function block(value:Null<Expr>):Array<Expr> {
		return switch value == null ? null : value.expr {
			case EBlock(entries): entries;
			case _: throw "expected a block";
		};
	}

	static function identityShape():Void {
		final file = "test/fixtures/project-macro-identity/src/Main.hx";
		final argument = macroArgument(file, "Identity", "preserve");
		final start = switch argument {
			case ESourceFunction(_, _, _, position): position.getIndex();
			case _: throw "identity fixture argument is not a source function";
		};
		final exported = roundTrip(file, argument).exported;
		require(exported.pos.file == file && exported.pos.min == start && exported.pos.max == start,
			"function position is not the zero-width start in the call file: "
			+ exported.pos.file
			+ " "
			+ exported.pos.min
			+ "-"
			+ exported.pos.max);
		switch exported.expr {
			case EFunction(FAnonymous, f):
				require(f.args.length == 1 && f.args[0].name == "label" && f.args[0].opt == false, "parameter changed");
				switch [f.args[0].type, f.ret] {
					case [
						TPath({pack: [], name: "String", params: []}),
						TPath({pack: [], name: "String", params: []})
					]:
					case _: throw "written signature changed";
				}
				final body = block(f.expr);
				require(body.length == 3, "function body statements changed");
				final group = block(body[0]);
				require(group.length == 2, "nested group lost its statements");
				switch group[0].expr {
					case EIf(_, {expr: EBlock([{expr: EReturn({expr: EConst(CIdent("label"))})}])}, null):
					case _: throw "guarded return changed";
				}
				switch body[2].expr {
					case EReturn({expr: EConst(CString("unreachable", DoubleQuotes))}):
					case _: throw "final return changed";
				}
				// The body group owns a later start; an identifier inside reuses its enclosing group's start.
				require(body[0].pos.min > start, "nested group did not keep its own start");
			case _:
				throw "identity argument is not an anonymous function";
		}
	}

	static function whileShape():Void {
		final file = "test/fixtures/expression_macro_while/Main.hx";
		final exported = roundTrip(file, macroArgument(file, "SyntaxArguments", "inspect")).exported;
		switch exported.expr {
			case EWhile({expr: EConst(CIdent("unresolvedCondition"))}, {
				expr: EBlock([
					{expr: ECall({expr: EConst(CIdent("unresolvedTick"))}, [{expr: EConst(CIdent("unresolvedCondition"))}])}
				])
			}, true):
			case _:
				throw "loop argument changed";
		}
	}

	static function positionsAndRejections():Void {
		final positions = new MacroSyntaxPositions("Main.hx");
		requireFailure("argument without a position", "macro syntax export:", "no recorded source position",
			() -> new MacroSyntaxExport(positions).argument(EIdent("value"), 0));
		requireFailure("lowered sequence", "macro syntax export:", "source brace grouping",
			() -> new MacroSyntaxExport(positions).argument(ESourceGroup([EDiscardThen(EInt(1), EInt(2))], new HxPos(4, 1, 5)), 0));
		final callPositions = new MacroSyntaxPositions("Main.hx");
		final anchor = new HxPos(7, 1, 8);
		new MacroSyntaxExport(callPositions).argument(ESourceGroup([], anchor), 0);
		final importer = new MacroSyntaxImport(callPositions);
		final created:Position = {file: "Other.hx", min: 3, max: 9};
		switch importer.result({expr: EBreak, pos: created}) {
			case EBreak(position):
				require(position == anchor, "a position the call did not export did not fall back to the argument start");
			case _:
				throw "break changed";
		}
		requireFailure("switch", "macro syntax import:", "switch", () -> importer.result({
			expr: ESwitch({expr: EConst(CIdent("x")), pos: created}, [], null),
			pos: created
		}));
		requireFailure("metadata", "macro syntax import:", "@:keep", () -> importer.result({
			expr: EMeta({name: ":keep", params: [], pos: created}, {expr: EConst(CIdent("x")), pos: created}),
			pos: created
		}));
		final ident = (name:String) -> ({expr: EConst(CIdent(name)), pos: created} : Expr);
		final keyValueLoop:Expr = {
			expr: EFor({expr: EBinop(OpArrow, ident("k"), {expr: EBinop(OpIn, ident("v"), ident("m")), pos: created}), pos: created}, ident("k")),
			pos: created
		};
		switch importer.result(keyValueLoop) {
			case ESourceFor(KeyValue("k", "v"), EIdent("m"), EIdent("k"), _):
			case _:
				throw "key/value loop binding changed";
		}
		switch importer.result({
			expr: EFunction(FArrow, {
				args: [
					{name: "items", type: TPath({pack: ["haxe"], name: "Rest", params: [TPType(TPath({pack: [], name: "Int"}))]})}
				],
				expr: ident("items")
			}),
			pos: created
		}) {
			case ESourceFunction(facts, _, _, _):
				final parameter = facts.getSignature().getParameters()[0];
				require(parameter.isRest && parameter.typeHint == "Int", "rest parameter changed");
			case _:
				throw "arrow function changed";
		}
		switch importer.result({expr: EConst(CIdent("Color")), pos: created}) {
			case EEnumValue("Color"):
			case _:
				throw "a standalone upper-case identifier is not an enum value as in the parser";
		}
		switch importer.result({expr: EField({expr: EConst(CIdent("Owner")), pos: created}, "field"), pos: created}) {
			case EField(EIdent("Owner"), "field"):
			case _:
				throw "a field owner became an enum value";
		}
		require(MacroSyntaxImport.typeText(TFunction([TPath({pack: [], name: "Int"}), TPath({pack: [], name: "String"})],
			TPath({pack: [], name: "Void"}))) == "(Int,String)->Void",
			"function type text changed");
		require(MacroSyntaxImport.typeText(TPath({
			pack: ["haxe", "ds"],
			name: "StringMap",
			params: [
				TPType(TPath({
					pack: [],
					name: "Int"
				}))
			]
		})) == "haxe.ds.StringMap<Int>", "type path text changed");
	}

	static function wireCoverage():Void {
		final p:Position = {file: "Cover.hx", min: 1, max: 2};
		function e(definition:ExprDef):Expr
			return {expr: definition, pos: p};
		// Every expression slot gets its own leaf, so a reader that reads two same-kind fields in
		// a different order than the writer changes the decoded tree and fails the checks below.
		var leaves = 0;
		function leaf():Expr
			return e(EConst(CIdent("l" + leaves++)));
		function id(name:String):Expr
			return e(EConst(CIdent(name)));
		final type = TPath({
			pack: ["haxe"],
			name: "Rest",
			params: [
				TPType(TAnonymous([
					{
						name: "a",
						doc: "doc",
						access: [APublic, AFinal],
						kind: FProp("get", "never", TOptional(TNamed("n", TParent(TIntersection([]))))),
						pos: p,
						meta: [
							{
								name: ":optional",
								params: null,
								pos: p
							}
						]
					}
				]))
			],
			sub: "Sub"
		});
		final everything = e(EBlock([
			e(EConst(CInt("1", null))),
			e(EConst(CFloat("1.5", "f64"))),
			e(EConst(CString("s", SingleQuotes))),
			e(EConst(CRegexp("a+", "g"))),
			e(EArray(id("array"), id("index"))),
			e(EBinop(OpAssignOp(OpNullCoal), id("left"), id("right"))),
			e(EField(leaf(), "f", Safe)),
			e(EParenthesis(leaf())),
			e(EObjectDecl([
				{
					field: "q",
					expr: leaf(),
					quotes: Quoted
				}
			])),
			e(EArrayDecl([leaf()])),
			e(ECall(id("callee"), [id("first"), id("second")])),
			e(ENew({pack: [], name: "T"}, [leaf()])),
			e(EUnop(OpSpread, false, leaf())),
			e(EVars([
				{
					name: "v",
					type: type,
					expr: null,
					isFinal: true,
					meta: [],
					namePos: p
				}
			])),
			e(EFunction(FNamed("f", true),
				{
					args: [
						{
							name: "a",
							opt: true,
							type: null,
							value: leaf(),
							meta: null
						}
					],
					ret: TFunction([], TExtend([{pack: [], name: "B"}], [])),
					expr: leaf(),
					params: [
						{
							name: "T",
							constraints: [type],
							params: [],
							meta: null,
							defaultType: null
						}
					]
				})),
			e(EFor(id("iterator"), id("loopBody"))),
			e(EIf(id("condition"), id("then"), null)),
			e(EWhile(id("whileCondition"), id("whileBody"), false)),
			e(ESwitch(leaf(), [
				{
					values: [leaf()],
					guard: leaf(),
					expr: null
				}
			],
				leaf())),
			e(ETry(leaf(), [{name: "c", type: null, expr: leaf()}])),
			e(EReturn(null)),
			e(EBreak),
			e(EContinue),
			e(EUntyped(leaf())),
			e(EThrow(leaf())),
			e(ECast(leaf(), null)),
			e(EDisplay(leaf(), DKPattern(true))),
			e(ETernary(id("test"), id("yes"), id("no"))),
			e(ECheckType(leaf(), TPath({
				pack: [],
				name: "T",
				params: [TPExpr(leaf())]
			}))),
			e(EMeta({name: "m", params: [leaf()], pos: p}, leaf())),
			e(EIs(leaf(), type))
		]));
		final payload = MacroSyntaxWire.encodeResult(everything);
		final decoded = MacroSyntaxWire.decodeResult(payload);
		require(MacroSyntaxWire.encodeResult(decoded) == payload, "full syntax payload is not stable across a decode");
		final entries = block(decoded);
		function name(value:Expr):String
			return switch value.expr {
				case EConst(CIdent(text)): text;
				case _: "<not an identifier>";
			};
		var checked = 0;
		for (entry in entries) {
			require(entry.pos.file == "Cover.hx" && entry.pos.min == 1 && entry.pos.max == 2, "decoded position fields changed");
			switch entry.expr {
				case EArray(array, index):
					require(name(array) == "array" && name(index) == "index", "EArray operands changed order");
					checked++;
				case EBinop(OpAssignOp(OpNullCoal), left, right):
					require(name(left) == "left" && name(right) == "right", "EBinop operands changed order");
					checked++;
				case ECall(callee, arguments):
					require(name(callee) == "callee" && arguments.length == 2 && name(arguments[0]) == "first" && name(arguments[1]) == "second",
						"ECall callee or arguments changed");
					checked++;
				case EFor(iterator, body):
					require(name(iterator) == "iterator" && name(body) == "loopBody", "EFor operands changed order");
					checked++;
				case EIf(condition, whenTrue, whenFalse):
					require(name(condition) == "condition" && name(whenTrue) == "then" && whenFalse == null, "EIf operands changed");
					checked++;
				case EWhile(condition, body, normal):
					require(name(condition) == "whileCondition" && name(body) == "whileBody" && !normal, "EWhile operands changed");
					checked++;
				case ETernary(test, yes, no):
					require(name(test) == "test" && name(yes) == "yes" && name(no) == "no", "ETernary operands changed order");
					checked++;
				case EFunction(FNamed("f", true), f):
					require(f.args.length == 1 && f.args[0].name == "a" && f.args[0].opt == true && f.params.length == 1 && f.params[0].name == "T",
						"function fields changed");
					checked++;
				case EVars([variable]):
					require(variable.name == "v" && variable.isFinal == true && variable.expr == null && variable.type != null, "variable fields changed");
					switch variable.type {
						case TPath(path):
							require(path.pack.join(".") == "haxe" && path.name == "Rest" && path.sub == "Sub" && path.params.length == 1,
								"type path fields changed");
						case _:
							throw "variable type changed";
					}
					checked++;
				case _:
			}
		}
		require(checked == 9, "decoded structure checks did not all run: " + checked);
		final failure = MacroSyntaxWire.encodeFailure("macro said no");
		require(MacroSyntaxWire.isFailure(failure)
			&& MacroSyntaxWire.decodeFailure(failure) == "macro said no", "failure payload changed");
		requireFailure("truncated", "macro syntax wire:", "truncated", () -> MacroSyntaxWire.decodeResult(payload.substr(0, payload.length - 3)));
		requireFailure("trailing", "macro syntax wire:", "trailing", () -> MacroSyntaxWire.decodeResult(payload + "_"));
		requireFailure("version", "macro syntax wire:", "version", () -> MacroSyntaxWire.decodeResult("hxhx-macro-syntax.v0\nR"));
		requireFailure("envelope", "macro syntax wire:", "envelope", () -> MacroSyntaxWire.decodeArguments(payload));
		requireFailure("constructor", "macro syntax wire:", "unknown expression constructor",
			() -> MacroSyntaxWire.decodeResult(MacroSyntaxWire.VERSION + "\nRS5:ENope"));
	}

	static function main():Void {
		identityShape();
		whileShape();
		positionsAndRejections();
		wireCoverage();
		Sys.println("M14_MACRO_SYNTAX_ROUND_TRIP:PASS");
	}
}
