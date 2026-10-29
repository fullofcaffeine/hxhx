import reflaxe.ocaml.target.OcamlTargetBindingFact;
import reflaxe.ocaml.target.OcamlTargetExpressionFact;
import reflaxe.ocaml.target.OcamlTargetFunctionFact;
import reflaxe.ocaml.target.OcamlTargetFunctionFact.OcamlTargetFunctionSignature;
import reflaxe.ocaml.target.OcamlTargetLiteralFact;
import reflaxe.ocaml.target.OcamlTargetProgramRequest;
import reflaxe.ocaml.target.OcamlTargetStaticCallFact;
import reflaxe.ocaml.target.OcamlTargetStatementFact;

/** Challenge the function boundary with corrupt identities and mismatched value types. */
class FunctionValuesValidation {
	/** Compile generated call syntax against independent effectful functions in Observer.ml. */
	public static function orderObserverSource():String {
		final left = OcamlTargetExpressionFact.directStaticCall("root/argument/0", new OcamlTargetStaticCallFact({
			moduleId: "Observer",
			sourceTypeName: "Observer",
			sourceFunctionName: "left",
			argumentTypeDisplays: [],
			returnTypeDisplay: "Int"
		}), []);
		final right = OcamlTargetExpressionFact.directStaticCall("root/argument/1", new OcamlTargetStaticCallFact({
			moduleId: "Observer",
			sourceTypeName: "Observer",
			sourceFunctionName: "right",
			argumentTypeDisplays: [],
			returnTypeDisplay: "Int"
		}), []);
		final call = OcamlTargetExpressionFact.directStaticCall("root", new OcamlTargetStaticCallFact({
			moduleId: "Observer",
			sourceTypeName: "Observer",
			sourceFunctionName: "combine",
			argumentTypeDisplays: ["Int", "Int"],
			returnTypeDisplay: "Int"
		}), [left, right]);
		final syntax = new reflaxe.ocaml.ast.OcamlASTPrinter().printExpr(reflaxe.ocaml.target.OcamlTargetExpressionLowerer.build(call));
		return "open Observer\nlet result = " + syntax + "\nlet () = assert_order result\n";
	}

	public static function check(request:OcamlTargetProgramRequest):Void {
		final choose = request.copyFunctions().filter(fn -> fn.sourceFunctionName == "choose")[0];
		final signature:OcamlTargetFunctionSignature = {
			moduleId: choose.moduleId,
			sourceTypeName: choose.sourceTypeName,
			sourceFunctionName: choose.sourceFunctionName,
			role: choose.role,
			argumentTypeDisplays: choose.copyArgumentTypeDisplays(),
			returnTypeDisplay: choose.returnTypeDisplay
		};
		final parameters = choose.copyParameters();
		reject(() -> new OcamlTargetFunctionFact(signature, choose.body, [parameters[1], parameters[0]]), "inconsistent parameter");
		reject(() -> new OcamlTargetFunctionFact(signature, choose.body, [parameters[0], parameters[0]]), "inconsistent parameter");
		final foreign = new OcamlTargetBindingFact("foreign", "root/parameter/0", Parameter, "first", "Int");
		reject(() -> new OcamlTargetFunctionFact(signature, choose.body, [foreign, parameters[1]]), "inconsistent parameter");
		final wrongReturn = OcamlTargetStatementFact.block("root", [
			OcamlTargetStatementFact.returnValue("root/block-item/0",
				OcamlTargetExpressionFact.literalExpression("root/block-item/0/return-value", OcamlTargetLiteralFact.boolLiteral(true, "Bool")))
		]);
		reject(() -> new OcamlTargetFunctionFact(signature, wrongReturn, parameters), "return control");
		final call = new OcamlTargetStaticCallFact({
			moduleId: "Main",
			sourceTypeName: "Main",
			sourceFunctionName: "choose",
			argumentTypeDisplays: ["Int", "Int"],
			returnTypeDisplay: "Int"
		});
		reject(() -> OcamlTargetExpressionFact.directStaticCall("root", call, []), "arguments do not match");
		final integer = OcamlTargetExpressionFact.literalExpression("root/argument/0", OcamlTargetLiteralFact.intLiteral(1, "Int"));
		final boolean = OcamlTargetExpressionFact.literalExpression("root/argument/1", OcamlTargetLiteralFact.boolLiteral(true, "Bool"));
		reject(() -> OcamlTargetExpressionFact.directStaticCall("root", call, [integer, boolean]), "exact ordered argument");
		final wrongCall = new OcamlTargetStaticCallFact({
			moduleId: "Main",
			sourceTypeName: "Main",
			sourceFunctionName: "choose",
			argumentTypeDisplays: ["Int", "Int"],
			returnTypeDisplay: "Bool"
		});
		if (!call.matchesFunction(choose) || wrongCall.matchesFunction(choose))
			throw "call result type was not checked against the selected function";
		final identity = choose.getCanonicalIdentity();
		parameters.reverse();
		signature.argumentTypeDisplays[0] = "Bool";
		if (choose.getCanonicalIdentity() != identity
			|| choose.copyParameters()[0].sourceName != "first"
			|| choose.copyArgumentTypeDisplays()[0] != "Int")
			throw "function exposes mutable parameter or signature storage";
	}

	static function reject(action:() -> Void, message:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(message) >= 0)
				return;
			throw error;
		}
		throw "expected function boundary rejection: " + message;
	}
}
