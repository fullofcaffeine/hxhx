import backend.ocaml.HxhxOcamlTargetFunctionAdapter;
import backend.ocaml.HxhxOcamlTargetProgramAdapter;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.target.OcamlTargetFunctionLowerer;
import reflaxe.ocaml.target.OcamlTargetProgramCore;
import reflaxe.ocaml.target.OcamlTargetProgramCore.OcamlTargetProgramPublisher;
import sys.io.File;

/** Checks an authored nonempty function through the native parser, typer, and shared target. **/
class NativeFunctionBodyFixture {
	/** Compare both hosts, reject corrupted bodies, then build and observe the native application. **/
	static function main():Void {
		final sourcePath = "test/reflaxe_ocaml_native_function_body/source/Main.hx";
		final resolved = new ResolvedModule("Main", sourcePath, ParserStage.parse(File.getContent(sourcePath), sourcePath));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final request = HxhxOcamlTargetProgramAdapter.fromProgram(new MacroExpandedProgram([typed], false), "Main");
		final functions = request.copyFunctions();
		if (functions.length != 1 || functions[0].body.copyChildren().length != 4)
			throw "native function body did not preserve all four source statements";
		final stock = StockFunctionBodyMacro.expected();
		if (functions[0].getCanonicalIdentity() != stock.identity)
			throw "stock and native hosts disagree on the authored function facts";
		if (new OcamlASTPrinter().printExpr(OcamlTargetFunctionLowerer.build(functions[0])) != stock.ocaml)
			throw "stock and native hosts disagree on generated function syntax";
		assertInvalidBodies(typed);
		assertUnsupportedSource("var value:Int;");
		assertUnsupportedSource("var value:Int = 7; value = 8;");
		assertUnsupportedSource("return;");
		assertUnsupportedSource("if (true) { var value:Int = 7; }");
		assertUnsupportedSource("main(7);");
		final repeated = HxhxOcamlTargetProgramAdapter.fromProgram(new MacroExpandedProgram([typed], false), "Main");
		if (repeated.getCanonicalIdentity() != request.getCanonicalIdentity())
			throw "a rejected body changed a later request's function facts";
		final plan = OcamlTargetProgramCore.lower(request);
		final output = ".tmp/native-function-body-" + Std.string(Date.now().getTime()) + "-" + Std.random(0x3fffffff);
		final executable = OcamlTargetProgramPublisher.publish(plan, output, "native-hxhx", true);
		final process = new sys.io.Process(executable, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final exitCode = process.exitCode();
		process.close();
		if (exitCode != 0 || stdout != "" || stderr != "")
			throw "native function body executable did not exit successfully with empty output";
		Sys.println("HXHX_OCAML_NATIVE_FUNCTION_BODY:PASS");
	}

	/** Reject incomplete or unsupported source before there is any target output. **/
	static function assertUnsupportedSource(body:String):Void {
		final source = "class Main { static function main():Void { " + body + " } }";
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final selection = selectFunction(TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved])));
		if (HxhxOcamlTargetFunctionAdapter.fromFunction(selection.owner, selection.fn) != null)
			throw "native function adapter admitted unsupported source: " + body;
	}

	/** Challenge declaration identity and visibility independently of ordinary source typing. **/
	static function assertInvalidBodies(module:TypedModule):Void {
		final selection = selectFunction(module);
		final fn = selection.fn;
		final statements = fn.getBody().getStatements();
		final fingerprint = fn.getBody().getSourceFingerprint();
		final missingDeclaration = fn.withBody(new TypedFunctionBody([statements[3]], fingerprint));
		if (HxhxOcamlTargetFunctionAdapter.fromFunction(selection.owner, missingDeclaration) != null)
			throw "a read without its exact declaration crossed the function boundary";
		assertRejected(() -> {
			HxhxOcamlTargetFunctionAdapter.fromFunction(selection.owner, fn.withBody(new TypedFunctionBody([statements[0], statements[0]], fingerprint)));
		}, "repeated local declaration identity");
		final local = statements[0].getLocalBindings()[0];
		final selfRead = TypedExpr.localRead(local.getSourceName(), local.getType(), null, local);
		final selfDeclaration = TypedStmt.variable(local.getSourceName(), "Int", selfRead, null, [], local);
		assertRejected(() -> {
			HxhxOcamlTargetFunctionAdapter.fromFunction(selection.owner, fn.withBody(new TypedFunctionBody([selfDeclaration], fingerprint)));
		}, "without a visible source binding");
		final nested = statements[2].getStatements()[0].getLocalBindings()[0];
		final escapingRead = TypedStmt.expressionStmt(TypedExpr.localRead(nested.getSourceName(), nested.getType(), null, nested), null);
		assertRejected(() -> {
			HxhxOcamlTargetFunctionAdapter.fromFunction(selection.owner,
				fn.withBody(new TypedFunctionBody([statements[2], escapingRead, statements[0]], fingerprint)));
		}, "without a visible source binding");
		final foreign = new TyLocalBinding(TyLocalId.forSourceDeclaration("Other.main", 0, Variable, "value"), "value", TyType.fromHintText("Int"), Variable);
		final foreignDeclaration = TypedStmt.variable("value", "Int", TypedExpr.intLiteral(7, foreign.getType(), null), null, [], foreign);
		assertRejected(() -> {
			HxhxOcamlTargetFunctionAdapter.fromFunction(selection.owner, fn.withBody(new TypedFunctionBody([foreignDeclaration], fingerprint)));
		}, "local from another function");
		assertRejected(() -> {
			HxhxOcamlTargetFunctionAdapter.fromFunction(selection.owner, fn.withBody(new TypedFunctionBody(statements, "stale")));
		}, "typed body revision mismatch");
	}

	static function selectFunction(module:TypedModule):{owner:TyNominalInfo, fn:TypedFunction} {
		for (typedClass in module.getTypedClasses()) {
			final owner = typedClass.getSemanticInfo();
			if (owner == null)
				continue;
			for (fn in typedClass.getFunctions())
				if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "main")
					return {owner: owner, fn: fn};
		}
		throw "fixture has no typed main function";
	}

	static function assertRejected(action:() -> Void, expected:String):Void {
		var actual = "";
		try {
			action();
		} catch (message:String) {
			actual = message;
		}
		if (actual.indexOf(expected) < 0)
			throw "expected rejection containing " + expected + ", got: " + actual;
	}
}
