import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlModuleAssembly;
import reflaxe.ocaml.ast.OcamlModuleValues.order as orderValues;

/** Checks forward calls, function recursion, lexical scope, and initializer order. */
class OcamlModuleValuesTest {
	public static function run():Void {
		final caller = functionPart("caller", EApp(EIdent("later"), [EConst(CUnit)]));
		final later = functionPart("later", EConst(CInt(8)));
		final fixed = render(orderValues("Example", [caller, later]));
		before(fixed, "let later", "let caller");
		if (render(orderValues("Example", [caller, later])) != fixed)
			throw "repeated assembly changed declaration output";
		final alreadyOrdered = [later, caller];
		if (render(orderValues("Example", alreadyOrdered)) != render(alreadyOrdered))
			throw "valid module text changed";

		final mutual = render(orderValues("Mutual", [caller, functionPart("later", EApp(EIdent("caller"), [EConst(CUnit)]))]));
		if (mutual.indexOf("let rec caller") < 0 || mutual.indexOf("and later") < 0)
			throw "mutually recursive functions lack a shared recursive declaration";

		final first = valuePart("first", EApp(EIdent("observe"), [EConst(CInt(1))]));
		final second = valuePart("second", EApp(EIdent("observe"), [EConst(CInt(2))]));
		final effects = render(orderValues("Effects", [first, caller, second, later]));
		before(effects, "let first", "let second");
		before(effects, "let later", "let caller");
		reject([valuePart("first", EIdent("second")), second], "initializer-cycle");
		reject([caller, OpaqueModuleText("(* external declarations *)"), later], "declaration-barrier");
		reject([
			caller,
			later,
			functionPart("raw", OcamlASTTraversalTest.rawInjectionExpression("unknown_value", []))
		], "opaque-value-dependency");
		reject([
			caller,
			ModuleDeclarations("", [IType([{name: "t", params: [], kind: Alias(TIdent("int"))}], false)]),
			later
		], "declaration-barrier");

		final shadowed = valuePart("local", EFun([PVar("later")], EIdent("later")));
		final lexical = [shadowed, later];
		if (render(orderValues("Lexical", lexical)) != render(lexical))
			throw "a function parameter became a module dependency";
		final localLet = functionPart("localLet", ELet("later", EConst(CInt(4)), EIdent("later"), false));
		if (render(orderValues("LexicalLet", [localLet, later])) != render([localLet, later]))
			throw "a local let became a module dependency";

		final marker = valuePart("marker", EConst(CUnit));
		final repeated = render(orderValues("Markers", [marker, caller, marker, later]));
		before(repeated, "let later", "let caller");
		reject([
			valuePart("tag", EConst(CInt(1))),
			functionPart("read", EIdent("tag")),
			caller,
			valuePart("tag", EConst(CInt(2))),
			later
		], "shadowed-owner");
	}

	static function functionPart(name:String, body:OcamlExpr):OcamlModulePart {
		return valuePart(name, EFun([PConst(CUnit)], body));
	}

	static function valuePart(name:String, value:OcamlExpr):OcamlModulePart {
		return ModuleDeclarations("", [ILet([{name: name, expr: value}], false)]);
	}

	static function render(parts:Array<OcamlModulePart>):String {
		final printer = new OcamlASTPrinter();
		return [
			for (part in parts)
				switch (part) {
					case ModuleDeclarations(header, items):
						header + printer.printModule(items);
					case OpaqueModuleText(text):
						text;
				}
		].join("\n\n");
	}

	static function before(text:String, first:String, second:String):Void {
		if (text.indexOf(first) < 0 || text.indexOf(second) < 0 || text.indexOf(first) >= text.indexOf(second))
			throw 'Expected $first before $second in $text';
	}

	static function reject(parts:Array<OcamlModulePart>, code:String):Void {
		var rejected = false;
		try {
			orderValues("Rejected", parts);
		} catch (message:String) {
			rejected = message.indexOf("ocaml-module-values:" + code) >= 0;
		}
		if (!rejected)
			throw "Expected module-value rejection: " + code;
	}
}
