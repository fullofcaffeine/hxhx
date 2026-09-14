import backend.ocaml.HxhxOcamlTargetProgramAdapter;
import reflaxe.ocaml.target.OcamlTargetProgramCore;
import reflaxe.ocaml.target.OcamlTargetProgramCore.OcamlTargetProgramPublisher;
import sys.io.File;

/** Exercises authored direct calls through the native compiler facts and shared target. **/
class SharedStaticCallsFixture {
	static function main():Void {
		final path = "test/reflaxe_ocaml_shared_static_calls/source/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final request = HxhxOcamlTargetProgramAdapter.fromProgram(new MacroExpandedProgram([typed], false), "Main");
		final plan = OcamlTargetProgramCore.lower(request);
		assertRejectedCalls();
		final declarations = backend.ocaml.HxhxOcamlTargetDeclarationAdapter.fromModules("fixture", [typed.getBackendProjection()]);
		assertRejected(() -> new reflaxe.ocaml.target.OcamlTargetProgramRequest("fixture", "Main", declarations, [],
			request.copyFunctions().filter(fn -> fn.sourceFunctionName != "middle")),
			"no admitted callee");
		final main = request.copyFunctions().filter(fn -> fn.sourceFunctionName == "main")[0];
		if (main.body.copyStaticCalls().map(call -> call.sourceFunctionName).join(",") != "middle,type,ignore")
			throw "authored call order or declaration identity changed";
		final foreignCall = reflaxe.ocaml.target.OcamlTargetExpressionFact.directStaticCall("root",
			new reflaxe.ocaml.target.OcamlTargetStaticCallFact({moduleId: "Other", sourceTypeName: "Other", sourceFunctionName: "middle"}));
		assertRejected(() -> new reflaxe.ocaml.target.OcamlTargetFunctionFact({
			moduleId: "Main",
			sourceTypeName: "Main",
			sourceFunctionName: "main",
			role: StaticFunction,
			argumentTypeDisplays: [],
			returnTypeDisplay: "Void"
		}, foreignCall), "cross-owner");
		assertRejected(() -> new reflaxe.ocaml.target.OcamlTargetFieldInitializerFact({
			moduleId: "Main",
			sourceTypeName: "Main",
			sourceFieldName: "value",
			role: StaticField,
			semanticTypeDisplay: "Int"
		}, foreignCall), "does not admit function calls");
		final conflicting = new reflaxe.ocaml.target.OcamlTargetFunctionFact({
			moduleId: "Main",
			sourceTypeName: "Main",
			sourceFunctionName: "middle",
			role: StaticFunction,
			argumentTypeDisplays: [],
			returnTypeDisplay: "Void"
		}, reflaxe.ocaml.target.OcamlTargetExpressionFact.block("root", "Void", []));
		assertRejected(() -> new reflaxe.ocaml.target.OcamlTargetProgramRequest("fixture", "Main", declarations, [],
			request.copyFunctions().concat([conflicting])),
			"conflicting function facts");
		final stock = StockStaticCallsMacro.expected();
		if (stock.length != request.copyFunctions().length)
			throw "host function inventories differ";
		for (fn in request.copyFunctions()) {
			final matches = stock.filter(value -> value.name == fn.sourceFunctionName);
			if (matches.length != 1
				|| matches[0].identity != fn.getCanonicalIdentity()
				|| matches[0].syntax != new reflaxe.ocaml.ast.OcamlASTPrinter().printExpr(reflaxe.ocaml.target.OcamlTargetFunctionLowerer.build(fn)))
				throw "stock/native call facts or syntax differ for " + fn.sourceFunctionName;
		}
		final output = ".tmp/shared-static-calls-" + Std.string(Date.now().getTime()) + "-" + Std.random(0x3fffffff);
		final executable = OcamlTargetProgramPublisher.publish(plan, output, "native-hxhx", true);
		final process = new sys.io.Process(executable, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		if (status != 0 || stdout != "" || stderr != "")
			throw "shared static call application did not exit successfully with empty output";
		Sys.println("REFLAXE_OCAML_SHARED_STATIC_CALLS:PASS");
	}

	/** Unsupported signatures and computed callees must reject the whole authored function. **/
	static function assertRejectedCalls():Void {
		final cases = [
			{member: "static function target(value:Int):Void {}", body: "target(1);"},
			{member: "static function target():Int { return 1; }", body: "target();"},
			{member: "static dynamic function target():Void {}", body: "target();"},
			{member: "static function target<T>():Void {}", body: "target();"},
			{member: "static function target():Void {}", body: "var local = target; local();"},
			{member: "", body: "missing();"}
		];
		for (item in cases) {
			final source = "class Main { static function main():Void { " + item.body + " } " + item.member + " }";
			final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
			final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
			for (cls in typed.getTypedClasses())
				for (fn in cls.getFunctions())
					if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "main"
						&& backend.ocaml.HxhxOcamlTargetFunctionAdapter.fromFunction(cls.getSemanticInfo(), fn) != null)
						throw "unsupported call admitted: " + item.body + item.member;
		}
	}

	static function assertRejected(action:() -> Void, expected:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(expected) >= 0)
				return;
			throw error;
		}
		throw "expected rejection: " + expected;
	}
}
