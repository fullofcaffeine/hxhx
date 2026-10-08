import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlCallableViewSyntax.adapt as adaptView;
import reflaxe.ocaml.ast.OcamlCallableViewSyntax.compare as compareViews;
import reflaxe.ocaml.ast.OcamlCallableViewSyntax.invocation as viewInvocation;
import reflaxe.ocaml.ast.OcamlCallableViewSyntax.identity as viewIdentity;
import reflaxe.ocaml.ast.OcamlCallableViewSyntax.origin as originView;
import reflaxe.ocaml.ast.OcamlCallableViewSyntax.literal as literalView;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlGenericCallEmitter.convertView;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.ast.OcamlTypeExpr;

/**
	Executes the callable storage operations with the native collector.

	The independent expected output checks identity across adapters, producer and
	comparison order, retained captures, and reclamation after the last view dies.
	This tests target syntax operations. The stored-callback source fixture still
	checks their eventual integration through the Haxe compiler.
**/
class OcamlCallableViewSyntaxTest {
	static var sequence = 0;

	static function fresh(role:String):String
		return "test_" + role + "_" + sequence++;

	static function call(name:String, arguments:Array<OcamlExpr>):OcamlExpr
		return EApp(EIdent(name), arguments);

	static function unitCall(name:String):OcamlExpr
		return call(name, [EConst(CUnit)]);

	static function print(value:OcamlExpr):OcamlExpr
		return call("print_endline", [value]);

	static function printBool(value:OcamlExpr):OcamlExpr
		return print(call("string_of_bool", [value]));

	static function withEffect(label:String, value:OcamlExpr):OcamlExpr
		return ESeq([print(EConst(CString(label))), value]);

	static function origin(value:OcamlExpr):OcamlExpr
		return originView(value, value -> call("Obj.repr", [value]), fresh);

	static function equal(left:OcamlExpr, right:OcamlExpr):OcamlExpr {
		return compareViews(left, right, (left, right) -> EBinop(PhysEq, left, right), fresh);
	}

	/** The test's selected conversion boxes an Int before an Obj.t callback invocation. */
	static function view(value:OcamlExpr):OcamlExpr {
		return convertView(CheckOcamlCallableViewConversions.selectedView("first"), value, "test-view", fresh, unexpectedRuntime);
	}

	static function unexpectedRuntime(role:String, symbol:String):OcamlExpr {
		throw "Int callback conversion requested an unexpected runtime helper: " + role + "/" + symbol;
	}

	/** An argument callback returned through two opposite conversions retains its origin. */
	static function higherOrder():OcamlExpr {
		final higherType = CheckOcamlCallableViewConversions.selectedCarrier("higherSource");
		final relay = EAnnot(origin(EFun([PVar("callback")], EIdent("callback"))), higherType);
		final adapted = convertView(CheckOcamlCallableViewConversions.selectedView("higherView"), relay, "test-higher", fresh, unexpectedRuntime);
		final number = literalView(EFun([PAnnot(PVar("value"), TIdent("int"))], EBinop(Add, EIdent("value"), EConst(CInt(1)))), fresh);
		final returned = EApp(viewInvocation(EIdent("higher")), [EIdent("number")]);
		return ELet("higher", adapted, ELet("number", number, ELet("returned", returned, ESeq([
			unitCall("Gc.full_major"),
			print(call("string_of_int", [EApp(viewInvocation(EIdent("returned")), [EConst(CInt(7))])])),
			printBool(equal(EIdent("returned"), EIdent("number")))
		]), false), false), false);
	}

	static function invokeInt(name:String):OcamlExpr {
		final result = EApp(viewInvocation(EIdent(name)), [EConst(CInt(7))]);
		return print(call("string_of_int", [EAnnot(call("Obj.obj", [result]), TIdent("int"))]));
	}

	/** Repeated lambda evaluation creates distinct Haxe functions even without captures. */
	static function literalOrigins():OcamlExpr {
		final functionValue:OcamlExpr = EFun([PAnnot(PVar("value"), TIdent("int"))], EBinop(Add, EIdent("value"), EConst(CInt(1))));
		final factory:OcamlExpr = EFun([PConst(CUnit)], literalView(functionValue, fresh));
		return ELet("declared", functionValue,
			ELet("make_literal", factory, ELet("literal_left", unitCall("make_literal"), ELet("literal_right", unitCall("make_literal"), ESeq([
				unitCall("Gc.full_major"),
				printBool(equal(origin(EIdent("declared")), origin(EIdent("declared")))),
				printBool(equal(EIdent("literal_left"), EIdent("literal_left"))),
				printBool(equal(EIdent("literal_left"), EIdent("literal_right"))),
				printBool(equal(EIdent("left"), EIdent("right"))),
				print(call("string_of_int", [EApp(viewInvocation(EIdent("literal_left")), [EConst(CInt(7))])])),
				print(call("string_of_int", [EApp(viewInvocation(EIdent("literal_right")), [EConst(CInt(7))])]))
			]), false), false), false), false);
	}

	/** A capture-free lambda's token lives with its view and is reclaimed after that view dies. */
	static function tokenLifetime():OcamlExpr {
		final token = literalView(EFun([PConst(CUnit)], EConst(CUnit)), fresh);
		final observed = call("Weak.check", [EIdent("token_observer"), EConst(CInt(0))]);
		final use = EFun([PConst(CUnit)], ELet("token_live", token, ESeq([
			call("Weak.set", [
				EIdent("token_observer"),
				EConst(CInt(0)),
				call("Some", [viewIdentity(EIdent("token_live"))])
			]),
			unitCall("Gc.full_major"),
			printBool(observed),
			// Keep the complete view live across collection, including its token.
			call("ignore", [call("Sys.opaque_identity", [EIdent("token_live")])])
		]), false));
		return ELet("token_observer", call("Weak.create", [EConst(CInt(1))]), ELet("use_token", use, ESeq([
			unitCall("use_token"),
			unitCall("Gc.full_major"),
			unitCall("Gc.full_major"),
			printBool(observed)
		]), false), false);
	}

	/** A weak observer must see the capture alive with a view and absent after its scope ends. */
	static function lifetime():OcamlExpr {
		final capture:OcamlExpr = EFun([PAnnot(PVar("value"), TIdent("Obj.t"))], call("Obj.repr", [
			EBinop(Add, EAnnot(call("Obj.obj", [EIdent("value")]), TIdent("int")), EUnop(Deref, EIdent("payload")))
		]));
		final install = EFun([PConst(CUnit)], ELet("payload", call("ref", [EConst(CInt(1))]), ESeq([
			call("Weak.set", [EIdent("observer"), EConst(CInt(0)), call("Some", [EIdent("payload")])]),
			view(literalView(capture, fresh))
		]), false));
		final observed = call("Weak.check", [EIdent("observer"), EConst(CInt(0))]);
		final use = EFun([PConst(CUnit)],
			ELet("escaped", unitCall("install"), ESeq([unitCall("Gc.full_major"), printBool(observed), invokeInt("escaped")]), false));
		return ELet("observer", call("Weak.create", [EConst(CInt(1))]), ELet("install", install, ELet("use", use, ESeq([
			unitCall("use"),
			unitCall("Gc.full_major"),
			unitCall("Gc.full_major"),
			printBool(observed)
		]), false), false), false);
	}

	static function program():OcamlExpr {
		final identity:OcamlExpr = EFun([PAnnot(PVar("value"), TIdent("Obj.t"))], EIdent("value"));
		final factory:OcamlExpr = EFun([PVar("offset")], literalView(EFun([PAnnot(PVar("value"), TIdent("Obj.t"))], call("Obj.repr", [
			EBinop(Add, EAnnot(call("Obj.obj", [EIdent("value")]), TIdent("int")), EIdent("offset"))
		])), fresh));
		var body:OcamlExpr = ESeq([
			invokeInt("first"),
			printBool(equal(EIdent("first"), EIdent("alias"))),
			printBool(equal(EIdent("first"), EIdent("second"))),
			printBool(equal(EIdent("first"), EIdent("source"))),
			printBool(equal(EIdent("first"), EIdent("third"))),
			printBool(equal(EIdent("left"), EIdent("right"))),
			printBool(equal(withEffect("left", EIdent("first")), withEffect("right", EIdent("second")))),
			unitCall("Gc.full_major"),
			invokeInt("first"),
			lifetime(),
			higherOrder(),
			literalOrigins(),
			tokenLifetime()
		]);
		final type = CheckOcamlCallableViewConversions.selectedCarrier("source");
		final bindings:Array<{name:String, value:OcamlExpr}> = [
			{name: "source", value: EAnnot(origin(withEffect("source", identity)), type)},
			{name: "first", value: view(withEffect("view", EIdent("source")))},
			{name: "second", value: view(EIdent("source"))},
			{name: "alias", value: EIdent("first")},
			{name: "third", value: adaptView(EIdent("first"), value -> value, fresh)},
			{name: "make", value: factory},
			{name: "left", value: call("make", [EConst(CInt(1))])},
			{name: "right", value: call("make", [EConst(CInt(1))])}
		];
		var index = bindings.length;
		while (index-- > 0)
			body = ELet(bindings[index].name, bindings[index].value, body, false);
		return body;
	}

	/** Bound native compilation and execution; either failure must fail the Haxe harness. */
	static function run(arguments:Array<String>):String {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30"].concat(arguments));
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "callable view native command failed: " + arguments.join(" ") + "\n" + output + errors;
		return output;
	}

	static function main():Void {
		final root = ".tmp/ocaml_callable_view_syntax";
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + "/main.ml", "let () = " + new OcamlASTPrinter().printExpr(program()) + "\n");
		run(["ocamlopt", "-o", root + "/main.exe", root + "/main.ml"]);
		final expected = "source\nview\n7\ntrue\ntrue\ntrue\ntrue\nfalse\nleft\nright\ntrue\n7\ntrue\n8\nfalse\n8\ntrue\ntrue\ntrue\nfalse\nfalse\n8\n8\ntrue\nfalse\n";
		final actual = run([root + "/main.exe"]);
		if (actual != expected)
			throw "callable view behavior differs\nexpected:\n" + expected + "actual:\n" + actual;
		Sys.println("OCAML_CALLABLE_VIEW_SYNTAX:PASS");
	}
}
