import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.target.OcamlTargetBindingFact;
import reflaxe.ocaml.target.OcamlTargetExpressionFact;
import reflaxe.ocaml.target.OcamlTargetExpressionLowerer;
import reflaxe.ocaml.target.OcamlTargetLiteralFact;
import reflaxe.ocaml.target.OcamlTargetStaticCallFact;

/** Prove branch laziness with independent effects and reject malformed conditional facts. */
class ConditionalValuesValidation {
	public static function observerSource():String {
		final expression = OcamlTargetExpressionFact.conditional("root", "Int", call("root/condition", "condition", "Bool"),
			branch("root/then", call("root/then/block-item/0", "left", "Int")), branch("root/else", call("root/else/block-item/0", "right", "Int")));
		final syntax = new OcamlASTPrinter().printExpr(OcamlTargetExpressionLowerer.build(expression));
		return "\nlet () = reset_conditional true; assert_conditional true ("
			+ syntax
			+ ")\nlet () = reset_conditional false; assert_conditional false ("
			+ syntax
			+ ")\n";
	}

	static function call(path:String, name:String, result:String):OcamlTargetExpressionFact
		return OcamlTargetExpressionFact.directStaticCall(path, new OcamlTargetStaticCallFact({
			moduleId: "Observer",
			sourceTypeName: "Observer",
			sourceFunctionName: name,
			argumentTypeDisplays: [],
			returnTypeDisplay: result
		}), []);

	static function branch(path:String, child:OcamlTargetExpressionFact):OcamlTargetExpressionFact
		return OcamlTargetExpressionFact.block(path, child.semanticTypeDisplay, [child]);

	public static function check():Void {
		final condition = OcamlTargetExpressionFact.literalExpression("root/condition", OcamlTargetLiteralFact.boolLiteral(true, "Bool"));
		final yes = branch("root/then", OcamlTargetExpressionFact.literalExpression("root/then/block-item/0", OcamlTargetLiteralFact.intLiteral(3, "Int")));
		final no = branch("root/else", OcamlTargetExpressionFact.literalExpression("root/else/block-item/0", OcamlTargetLiteralFact.intLiteral(9, "Int")));
		reject(() -> OcamlTargetExpressionFact.conditional("root", "Int", yes, yes, no), "child path");
		final wrongCondition = OcamlTargetExpressionFact.literalExpression("root/condition", OcamlTargetLiteralFact.intLiteral(1, "Int"));
		reject(() -> OcamlTargetExpressionFact.conditional("root", "Int", wrongCondition, yes, no), "Boolean condition");
		reject(() -> OcamlTargetExpressionFact.conditional("root", "Bool", condition, yes, no), "exact branch result");
		final bare = OcamlTargetExpressionFact.literalExpression("root/else", OcamlTargetLiteralFact.intLiteral(9, "Int"));
		reject(() -> OcamlTargetExpressionFact.conditional("root", "Int", condition, yes, bare), "scoped branches");

		final local = new OcamlTargetBindingFact("owner", "root/then/block-item/0/binding", Variable, "value", "Int");
		final declaration = OcamlTargetExpressionFact.variableDeclaration("root/then/block-item/0", local,
			OcamlTargetExpressionFact.literalExpression("root/then/block-item/0/initializer", OcamlTargetLiteralFact.intLiteral(3, "Int")));
		final scoped = OcamlTargetExpressionFact.block("root/then", "Int", [
			declaration,
			OcamlTargetExpressionFact.localRead("root/then/block-item/1", "Int", local)
		]);
		final escaped = branch("root/else", OcamlTargetExpressionFact.localRead("root/else/block-item/0", "Int", local));
		final invalid = OcamlTargetExpressionFact.conditional("root", "Int", condition, scoped, escaped);
		reject(() -> invalid.validateClosedBindings(), "visible source binding");
	}

	static function reject(action:() -> Void, message:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(message) >= 0)
				return;
			throw error;
		}
		throw "expected conditional rejection: " + message;
	}
}
