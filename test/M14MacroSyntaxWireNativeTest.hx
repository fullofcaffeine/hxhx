import haxe.macro.Expr;
import hxhxmacrohost.MacroSyntaxWire;

/**
	`MacroSyntaxWire` must give the same payload when it runs inside a Stage3-compiled program,
	which is how it runs inside a project macro plugin.

	The interpreter encodes two payloads: the exported identity fixture argument and a value that
	uses many `Expr` constructors and records. A small program compiled through the production
	`Stage3Compiler` request path (`--hxhx-stage3`, the plugin's emitter) decodes each payload and
	encodes it again. Its output must equal the interpreter's input byte for byte. A decode or
	encode difference between the two backends, including a changed field order, fails here.
**/
class M14MacroSyntaxWireNativeTest {
	static final directory = ".tmp/macro_syntax_wire_native";

	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function identityPayload():String {
		final file = "test/fixtures/project-macro-identity/src/Main.hx";
		final decl = ParserStage.parse(sys.io.File.getContent(file), file).getDecl();
		for (functionDecl in HxClassDecl.getFunctions(HxModuleDecl.getMainClass(decl)))
			for (statement in HxFunctionDecl.getBody(functionDecl))
				switch statement {
					case SVar("check", _, ECall(_, [argument]), _, _):
						return MacroSyntaxWire.encodeResult(new MacroSyntaxExport(new MacroSyntaxPositions(file)).argument(argument, 0));
					case _:
				}
		throw "identity fixture lost its macro call";
	}

	static function coveragePayload():String {
		final p:Position = {file: "Cover.hx", min: 3, max: 9};
		var leaves = 0;
		function e(definition:ExprDef):Expr
			return {expr: definition, pos: p};
		function leaf():Expr
			return e(EConst(CIdent("l" + leaves++)));
		final type = TPath({
			pack: ["haxe", "ds"],
			name: "Map",
			params: [TPType(TPath({pack: [], name: "Int"})), TPExpr(leaf())],
			sub: "Sub"
		});
		return MacroSyntaxWire.encodeResult(e(EBlock([
			e(EConst(CInt("7", null))),
			e(EConst(CFloat("1.5", "f64"))),
			e(EConst(CString("s", SingleQuotes))),
			e(EConst(CRegexp("a+", "g"))),
			e(EArray(leaf(), leaf())),
			e(EBinop(OpAssignOp(OpAdd), leaf(), leaf())),
			e(EField(leaf(), "f", Safe)),
			e(EObjectDecl([
				{
					field: "q",
					expr: leaf(),
					quotes: Quoted
				}
			])),
			e(ECall(leaf(), [leaf(), leaf()])),
			e(ENew({pack: [], name: "T"}, [leaf()])),
			e(EUnop(OpNeg, true, leaf())),
			e(EVars([
				{
					name: "v",
					type: type,
					expr: leaf(),
					isFinal: true,
					isStatic: false,
					meta: [],
					namePos: p
				}
			])),
			e(EFunction(FNamed("f", false),
				{
					args: [
						{
							name: "a",
							opt: true,
							type: TFunction([type], TParent(type)),
							value: leaf(),
							meta: null
						}
					],
					ret: TAnonymous([
						{
							name: "x",
							kind: FVar(type, null),
							pos: p,
							access: [APublic],
							meta: [{name: ":optional", params: [leaf()], pos: p}]
						}
					]),
					expr: leaf(),
					params: [
						{
							name: "T",
							constraints: [type],
							params: [{name: "U"}],
							meta: null,
							defaultType: null
						}
					]
				})),
			e(EFor(leaf(), leaf())),
			e(EIf(leaf(), leaf(), null)),
			e(EWhile(leaf(), leaf(), false)),
			e(ESwitch(leaf(), [{values: [leaf()], guard: leaf(), expr: null}], leaf())),
			e(ETry(leaf(), [{name: "c", type: type, expr: leaf()}])),
			e(EReturn(null)),
			e(EBreak),
			e(EContinue),
			e(EUntyped(leaf())),
			e(EThrow(leaf())),
			e(ECast(leaf(), null)),
			e(EDisplay(leaf(), DKPattern(false))),
			e(ETernary(leaf(), leaf(), leaf())),
			e(ECheckType(leaf(), TIntersection([type, type]))),
			e(EMeta({
				name: ":m",
				params: [leaf()],
				pos: p
			}, leaf())),
			e(EIs(leaf(), TNamed("n", TOptional(type))))
		])));
	}

	/** A Haxe double-quoted literal for any payload text. */
	static function quote(text:String):String {
		final out = new StringBuf();
		out.add("\"");
		for (index in 0...text.length) {
			final character = text.charAt(index);
			out.add(switch character {
				case "\\": "\\\\";
				case "\"": "\\\"";
				case "\n": "\\n";
				case "\r": "\\r";
				case "\t": "\\t";
				case _: character;
			});
		}
		out.add("\"");
		return out.toString();
	}

	static function main():Void {
		sys.FileSystem.createDirectory(directory + "/src");
		final payloads = [identityPayload(), coveragePayload()];
		// The payloads are embedded as string literals: the program only exercises the codec.
		final literals = [for (payload in payloads) quote(payload)];
		sys.io.File.saveContent(directory
			+ "/src/Main.hx", "class Main {
			static function main():Void {
				for (payload in ["
			+ literals.join(", ")
			+ "])
					Sys.println(hxhxmacrohost.MacroSyntaxWire.encodeResult(hxhxmacrohost.MacroSyntaxWire.decodeResult(payload)));
			}
		}");
		final request = hxhx.CompilationRequestContext.server(1);
		final code = hxhx.Stage3Compiler.runRequest([
			"--hxhx-no-run",
			"--hxhx-out",
			directory + "/stage3",
			"-cp",
			"packages/hxhx-core/src",
			"-cp",
			directory + "/src",
			"-main",
			"Main"
		], request);
		final output = new StringBuf();
		for (event in request.output.events())
			output.add(event.text);
		request.close(code == 0);
		require(code == 0, "the payload program did not compile natively:\n" + output.toString());
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", directory + "/stage3/out.exe"]);
		final printed = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final exit = process.exitCode();
		process.close();
		require(exit == 0, "the native payload program failed (exit " + exit + "): " + errors);
		require(printed == payloads.join("\n") + "\n", "native decode and encode changed a payload:\n" + printed);
		Sys.println("MACRO_SYNTAX_WIRE_NATIVE:PASS");
	}
}
