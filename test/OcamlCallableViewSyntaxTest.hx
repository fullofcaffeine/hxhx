import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlCallableViewSyntax.adapt as adaptView;
import reflaxe.ocaml.ast.OcamlCallableViewSyntax.compare as compareViews;
import reflaxe.ocaml.ast.OcamlCallableViewSyntax.invocation as viewInvocation;
import reflaxe.ocaml.ast.OcamlCallableViewSyntax.identity as viewIdentity;
import reflaxe.ocaml.ast.OcamlCallableViewSyntax.produce as produceView;
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

	static function origin(value:OcamlExpr):OcamlExpr {
		final producer = CheckOcamlCallableViewConversions.selectedProducer("source");
		CheckOcamlCallableViewReports.verifyLocalReport(producer.report);
		return producerWrite(producer.report, value);
	}

	/** Exercise the production write emitter with a plan decoded at the report boundary. */
	static function producerWrite(report:String, value:OcamlExpr):OcamlExpr {
		final decision = reflaxe.ocaml.reports.OcamlCallableViewReport.localFromReport(haxe.Json.parse(report));
		final runtime = new reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority();
		runtime.beginProgram(decision.binding.programRevision, "portable");
		return reflaxe.ocaml.ast.OcamlCallableViewWriteSyntax.build({
			decision: decision,
			value: value,
			fresh: fresh,
			profile: "portable",
			requirements: reflaxe.ocaml.lowered.OcamlCallableViewRuntime.requirements(decision),
			finalRuntimeUses: runtime
		});
	}

	/** The typed lambda initializer selects allocation; the native syntax cannot infer it. */
	static function sourceLiteral(value:OcamlExpr):OcamlExpr {
		final producer = CheckOcamlCallableViewConversions.selectedProducer("number");
		CheckOcamlCallableViewReports.verifyLocalReport(producer.report);
		return producerWrite(producer.report, value);
	}

	/** Construct and adapt a direct static producer while preserving its declaration identity. */
	static function directProducer():OcamlExpr {
		final producer = CheckOcamlCallableViewConversions.selectedProducer("direct");
		CheckOcamlCallableViewReports.verifyLocalReport(producer.report);
		final produced = producerWrite(producer.report, EIdent("declared_source"));
		return ELet("direct", produced, ESeq([invokeInt("direct"), printBool(equal(EIdent("direct"), EIdent("source")))]), false);
	}

	/** Return emission uses the same value adapter as local writes, with separate source ownership. */
	static function returnValue(decision:reflaxe.ocaml.lowered.OcamlCallableReturnContract.OcamlCallableReturnDecision, value:OcamlExpr):OcamlExpr {
		final operation = reflaxe.ocaml.lowered.OcamlCallableReturnContract.operation(decision);
		final runtime = new reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority();
		runtime.beginProgram(decision.binding.programRevision, "portable");
		return reflaxe.ocaml.ast.OcamlCallableValueSyntax.build({
			operation: operation,
			value: value,
			fresh: fresh,
			profile: "portable",
			requirements: reflaxe.ocaml.lowered.OcamlCallableViewRuntime.valueRequirements(operation),
			finalRuntimeUses: runtime
		});
	}

	/** Literal returns allocate once; parameter and call-result returns preserve the producer's token. */
	static function returnedValues():OcamlExpr {
		final declared = EFun([PAnnot(PVar("value"), TIdent("int"))], EBinop(Add, EIdent("value"), EConst(CInt(1))));
		final bindings:Array<{name:String, value:OcamlExpr}> = [
			{name: "return_declared", value: declared},
			{
				name: "return_literal",
				value: EFun([PConst(CUnit)], returnValue(CheckOcamlCallableReturnPlan.selected("literal"), withEffect("return-producer", declared)))
			},
			{name: "return_preserve", value: EFun([PVar("callback")], returnValue(CheckOcamlCallableReturnPlan.selected("preserve"), EIdent("callback")))},
			{
				name: "return_static",
				value: EFun([PConst(CUnit)], returnValue(CheckOcamlCallableReturnPlan.selected("staticCallback"), EIdent("return_declared")))
			},
			{name: "return_forward", value: EFun([PConst(CUnit)], returnValue(CheckOcamlCallableReturnPlan.selected("forwarded"), unitCall("return_literal")))},
			{name: "return_first", value: unitCall("return_literal")},
			{name: "return_second", value: unitCall("return_literal")},
			{name: "return_preserved", value: call("return_preserve", [EIdent("return_first")])},
			{name: "return_forwarded", value: unitCall("return_forward")}
		];
		var body = ESeq([
			unitCall("Gc.full_major"),
			printBool(equal(EIdent("return_first"), EIdent("return_second"))),
			printBool(equal(EIdent("return_preserved"), EIdent("return_first"))),
			printBool(equal(unitCall("return_static"), unitCall("return_static"))),
			printBool(equal(EIdent("return_forwarded"), unitCall("return_forward"))),
			print(call("string_of_int", [EApp(viewInvocation(EIdent("return_forwarded")), [EConst(CInt(7))])]))
		]);
		var index = bindings.length;
		while (index-- > 0)
			body = ELet(bindings[index].name, bindings[index].value, body, false);
		return body;
	}

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
		final relay = EAnnot(produceView(CheckOcamlCallableViewConversions.selectedOrigin("higherSource"), EFun([PVar("callback")], EIdent("callback")),
			fresh), higherType);
		final adapted = convertView(CheckOcamlCallableViewConversions.selectedView("higherView"), relay, "test-higher", fresh, unexpectedRuntime);
		final number = sourceLiteral(EFun([PAnnot(PVar("value"), TIdent("int"))], EBinop(Add, EIdent("value"), EConst(CInt(1)))));
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
		final factory:OcamlExpr = EFun([PConst(CUnit)], sourceLiteral(functionValue));
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
			tokenLifetime(),
			directProducer(),
			returnedValues()
		]);
		final type = CheckOcamlCallableViewConversions.selectedCarrier("source");
		final bindings:Array<{name:String, value:OcamlExpr}> = [
			{name: "declared_source", value: identity},
			{name: "source", value: EAnnot(origin(withEffect("source", EIdent("declared_source"))), type)},
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
		final expected = "source\nview\n7\ntrue\ntrue\ntrue\ntrue\nfalse\nleft\nright\ntrue\n7\ntrue\n8\nfalse\n8\ntrue\ntrue\ntrue\nfalse\nfalse\n8\n8\ntrue\nfalse\n7\ntrue\nreturn-producer\nreturn-producer\nreturn-producer\nfalse\ntrue\ntrue\nreturn-producer\nfalse\n8\n";
		final actual = run([root + "/main.exe"]);
		if (actual != expected)
			throw "callable view behavior differs\nexpected:\n" + expected + "actual:\n" + actual;
		Sys.println("OCAML_CALLABLE_VIEW_SYNTAX:PASS");
	}
}
