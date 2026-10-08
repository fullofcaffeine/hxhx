import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlCallableViewSyntax.adapt as adaptView;
import reflaxe.ocaml.ast.OcamlCallableViewSyntax.carrier as viewCarrier;
import reflaxe.ocaml.ast.OcamlCallableViewSyntax.compare as compareViews;
import reflaxe.ocaml.ast.OcamlCallableViewSyntax.invocation as viewInvocation;
import reflaxe.ocaml.ast.OcamlCallableViewSyntax.origin as originView;
import reflaxe.ocaml.ast.OcamlExpr;
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
		return adaptView(value, function(invocation) {
			final argument = fresh("argument");
			return EFun([PAnnot(PVar(argument), TIdent("int"))], EApp(invocation, [call("Obj.repr", [EIdent(argument)])]));
		}, fresh);
	}

	static function invokeInt(name:String):OcamlExpr {
		final result = EApp(viewInvocation(EIdent(name)), [EConst(CInt(7))]);
		return print(call("string_of_int", [EAnnot(call("Obj.obj", [result]), TIdent("int"))]));
	}

	/** A weak observer must see the capture alive with a view and absent after its scope ends. */
	static function lifetime():OcamlExpr {
		final capture:OcamlExpr = EFun([PAnnot(PVar("value"), TIdent("Obj.t"))], call("Obj.repr", [
			EBinop(Add, EAnnot(call("Obj.obj", [EIdent("value")]), TIdent("int")), EUnop(Deref, EIdent("payload")))
		]));
		final install = EFun([PConst(CUnit)], ELet("payload", call("ref", [EConst(CInt(1))]), ESeq([
			call("Weak.set", [EIdent("observer"), EConst(CInt(0)), call("Some", [EIdent("payload")])]),
			view(origin(capture))
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
		final factory:OcamlExpr = EFun([PVar("offset")], EFun([PAnnot(PVar("value"), TIdent("Obj.t"))], call("Obj.repr", [
			EBinop(Add, EAnnot(call("Obj.obj", [EIdent("value")]), TIdent("int")), EIdent("offset"))
		])));
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
			lifetime()
		]);
		final type = viewCarrier(TArrow(TIdent("Obj.t"), TIdent("Obj.t")), TIdent("Obj.t"));
		final bindings:Array<{name:String, value:OcamlExpr}> = [
			{name: "source", value: EAnnot(origin(withEffect("source", identity)), type)},
			{name: "first", value: view(withEffect("view", EIdent("source")))},
			{name: "second", value: view(EIdent("source"))},
			{name: "alias", value: EIdent("first")},
			{name: "third", value: adaptView(EIdent("first"), value -> value, fresh)},
			{name: "make", value: factory},
			{name: "left", value: origin(call("make", [EConst(CInt(1))]))},
			{name: "right", value: origin(call("make", [EConst(CInt(1))]))}
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
		final expected = "source\nview\n7\ntrue\ntrue\ntrue\ntrue\nfalse\nleft\nright\ntrue\n7\ntrue\n8\nfalse\n";
		final actual = run([root + "/main.exe"]);
		if (actual != expected)
			throw "callable view behavior differs\nexpected:\n" + expected + "actual:\n" + actual;
		Sys.println("OCAML_CALLABLE_VIEW_SYNTAX:PASS");
	}
}
