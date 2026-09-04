package backend.ocaml;

import reflaxe.ocaml.target.OcamlTargetLiteralFact;

/** Copies admitted native hxhx literal nodes into target-owned facts. **/
class HxhxOcamlTargetLiteralAdapter {
	public static function fromExpression(expression:TypedExpr):Null<OcamlTargetLiteralFact> {
		if (expression == null)
			throw "native OCaml literal adapter requires a typed expression";
		final typeDisplay = expression.getType().getCanonicalDisplay();
		return switch (expression.getTag()) {
			case NullValue: OcamlTargetLiteralFact.nullValue(typeDisplay);
			case ThisValue: OcamlTargetLiteralFact.thisValue(typeDisplay);
			case SuperValue: OcamlTargetLiteralFact.superValue(typeDisplay);
			case BoolValue: OcamlTargetLiteralFact.boolLiteral(expression.getBoolValue(), typeDisplay);
			case IntValue: OcamlTargetLiteralFact.intLiteral(expression.getIntValue(), typeDisplay);
			case StringValue:
				final values = expression.getTexts();
				if (values.length != 1)
					throw "native OCaml string literal has no exact value";
				OcamlTargetLiteralFact.stringLiteral(values[0], typeDisplay);
			case FloatValue | EnumValue | LocalRead | NameRead | FieldRead | NullSafeFieldRead | Call | MacroExpr | MacroType | Lambda | SwitchExpr |
				NewValue | Unary | Binary | Assign | CompoundAssign | Ternary | Anonymous | ArrayComprehension | ArrayDecl | ArrayAccess | Range | Cast |
				Untyped | Opaque | Block | Temporary | ReturnExpr | VariableDeclarations | VariableDeclaration | WhileExpr | BreakExpr | ContinueExpr:
				null;
		};
	}
}
