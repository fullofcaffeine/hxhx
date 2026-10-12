import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.target.OcamlTargetBindingFact;
import reflaxe.ocaml.target.OcamlTargetExpressionFact;
import reflaxe.ocaml.target.OcamlTargetExpressionFact.OcamlTargetBinaryOperator;
import reflaxe.ocaml.target.OcamlTargetExpressionLowerer;
import reflaxe.ocaml.target.OcamlTargetLiteralFact;
import reflaxe.ocaml.target.OcamlTargetStaticCallFact;

/** Check ordered effects and lazy exceptions independently from both host adapters. */
class BinaryValuesValidation {
	public static function observerSource():String {
		final lines = new Array<String>();
		for (operation in [IntEqual, IntNotEqual]) {
			final fact = OcamlTargetExpressionFact.binary("root", operation, call("root/left", "left", "Int"), call("root/right", "right", "Int"));
			final syntax = new OcamlASTPrinter().printExpr(OcamlTargetExpressionLowerer.build(fact));
			final expected = operation == IntEqual ? "false" : "true";
			lines.push('let () = events := []; assert (($syntax) = $expected); assert (!events = ["left"; "right"])');
		}
		for (operation in [BooleanAnd, BooleanOr]) {
			final fact = OcamlTargetExpressionFact.binary("root", operation, call("root/left", "binary_left", "Bool"),
				call("root/right", "binary_right", "Bool"));
			final syntax = new OcamlASTPrinter().printExpr(OcamlTargetExpressionLowerer.build(fact));
			for (left in [false, true])
				for (right in [false, true]) {
					final expected = operation == BooleanAnd ? left && right : left || right;
					final evaluatesRight = operation == BooleanAnd ? left : !left;
					final expectedEvents = evaluatesRight ? '["left"; "right"]' : '["left"]';
					lines.push('let () = reset_binary $left $right false; assert (($syntax) = $expected); assert (!events = $expectedEvents)');
					// Repeat with a throwing right operand. A selected exception must
					// propagate; an unselected operand must produce no effect at all.
					lines.push('let () = reset_binary $left $right true; let raised = (try ignore ($syntax); false with Binary_right -> true) in assert (raised = $evaluatesRight); assert (!events = $expectedEvents)');
				}
		}
		return "\n" + lines.join("\n") + "\n";
	}

	static function call(path:String, name:String, result:String):OcamlTargetExpressionFact
		return OcamlTargetExpressionFact.directStaticCall(path, new OcamlTargetStaticCallFact({
			moduleId: "Observer",
			sourceTypeName: "Observer",
			sourceFunctionName: name,
			argumentTypeDisplays: [],
			returnTypeDisplay: result
		}), []);

	public static function check():Void {
		final left = OcamlTargetExpressionFact.literalExpression("root/left", OcamlTargetLiteralFact.intLiteral(3, "Int"));
		final right = OcamlTargetExpressionFact.literalExpression("root/right", OcamlTargetLiteralFact.intLiteral(9, "Int"));
		reject(() -> OcamlTargetExpressionFact.binary("root", IntEqual, right, left), "operand paths and types");
		reject(() -> OcamlTargetExpressionFact.binary("root", BooleanOr, left, right), "operand paths and types");
		final boolean = OcamlTargetExpressionFact.literalExpression("root/right", OcamlTargetLiteralFact.boolLiteral(true, "Bool"));
		reject(() -> OcamlTargetExpressionFact.binary("root", IntNotEqual, left, boolean), "operand paths and types");
		if (OcamlTargetExpressionFact.binary("root", IntEqual, left, right)
			.getCanonicalIdentity() == OcamlTargetExpressionFact.binary("root", IntNotEqual, left, right)
			.getCanonicalIdentity())
			throw "binary identity lost its operation";

		final binding = new OcamlTargetBindingFact("owner", "root/left/block-item/0/binding", Variable, "value", "Int");
		final scoped = OcamlTargetExpressionFact.block("root/left", "Int", [
			OcamlTargetExpressionFact.variableDeclaration("root/left/block-item/0", binding,
				OcamlTargetExpressionFact.literalExpression("root/left/block-item/0/initializer", OcamlTargetLiteralFact.intLiteral(3, "Int"))),
			OcamlTargetExpressionFact.localRead("root/left/block-item/1", "Int", binding)
		]);
		final escaped = OcamlTargetExpressionFact.localRead("root/right", "Int", binding);
		reject(() -> OcamlTargetExpressionFact.binary("root", IntEqual, scoped, escaped).validateClosedBindings(), "visible source binding");
	}

	static function reject(action:() -> Void, message:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(message) >= 0)
				return;
			throw error;
		}
		throw "expected binary rejection: " + message;
	}
}
