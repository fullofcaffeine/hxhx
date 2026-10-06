/**
	Recover authored syntax from a structurally typed quote without backend changes.
	Quoted nodes retain source names and annotations. This view adds no selected
	type ascriptions, target names, or executable control transport.
 */
function expression(node:TypedExpr):HxExpr {
	final texts = node.getTexts();
	final children = node.getExpressions();
	final position = node.getPosition() == null ? HxPos.unknown() : node.getPosition();
	function child(index:Int):HxExpr
		return expression(children[index]);
	function tail(start:Int):Array<HxExpr>
		return [for (index in start...children.length) child(index)];
	return switch node.getTag() {
		case Parenthesized: EParenthesized(child(0), position);
		case PrivateAccess: EPrivateAccess(child(0), position);
		case NullValue: ENull;
		case BoolValue: EBool(node.getBoolValue());
		case StringValue: EString(texts[0]);
		case IntValue: EInt(node.getIntValue());
		case FloatValue: EFloat(node.getFloatValue());
		case EnumValue: EEnumValue(texts[0]);
		case ThisValue: EThis;
		case SuperValue: ESuper;
		case LocalRead | NameRead: EIdent(texts[0]);
		case FieldRead: EField(child(0), texts[0]);
		case NullSafeFieldRead: ENullSafeField(child(0), texts[0]);
		case Call: ECall(child(0), tail(1));
		case TargetScope: throw "resolved native syntax cannot supply an authored macro quote";
		case FeatureDefinition: ECall(EIdent("__define_feature__"), [HxExpr.EString(texts[0])].concat(tail(0)));
		case FeatureSelection: ECall(EIdent("__feature__"), [HxExpr.EString(texts[0])].concat(tail(0)));
		case MacroExpr: EMacroExpr(child(0), texts);
		case MacroType: EMacroType(texts[0]);
		case Lambda: ELambda(texts, child(0), node.getLambdaSignature());
		case SourceGroup: ESourceGroup(tail(0), position);
		case SourceIf: ESourceIf(child(0), child(1), children.length == 3 ? child(2) : null, position);
		case SourceFor: ESourceFor(HxForBinding.fromNames(node.getTexts()), child(0), child(1), position);
		case SourceTry: ESourceTry(node.getSourceCatches(), tail(0), position);
		case ThrowExpr: EThrow(child(0), position);
		case SourceFunction:
			final facts = node.getSourceFunction();
			if (facts == null)
				throw "typed source function lost its authored facts";
			ESourceFunction(facts, child(0), tail(1), position);
		case ReturnExpr: EReturn(children.length == 0 ? null : child(0));
		case VariableDeclarations: EVars(tail(0));
		case VariableDeclaration:
			HxExprVarDecl.make(texts[0], texts[1], children.length == 0 ? null : child(0), position, node.getVariableIsFinal(), node.getVariableIsStatic());
		case WhileExpr: EWhile(child(0), tail(1), node.getBoolValue(), position, node.getWhileKind());
		case BreakExpr: EBreak(position);
		case ContinueExpr: EContinue(position);
		case SwitchExpr: ESwitch(child(0), node.getPatterns(), tail(1));
		case NewValue: ENew(texts[0], tail(0));
		case Unary: EUnop(node.getUnaryOperator(), node.getUnaryFixity(), child(0));
		case Binary | CompoundAssign: EBinop(texts[0], child(0), child(1));
		case Assign: EBinop("=", child(0), child(1));
		case Ternary: ETernary(child(0), child(1), child(2));
		case Anonymous: EAnon(texts, tail(0));
		case ArrayComprehension: EArrayComprehension(texts[0], child(0), node.getBoolValue() ? child(1) : null, child(node.getBoolValue() ? 2 : 1));
		case ArrayDecl: EArrayDecl(tail(0));
		case ArrayAccess: EArrayAccess(child(0), child(1));
		case Range: ERange(child(0), child(1));
		case Cast: ECast(child(0), texts[0]);
		case Untyped: EUntyped(child(0));
		case Opaque:
			switch node.getOpaqueKind() {
				case TryCatch: ETryCatchRaw(texts[0]);
				case Switch: ESwitchRaw(texts[0]);
				case Unsupported: EUnsupported(texts[0]);
				case null: throw "typed source syntax lost its opaque kind";
			}
		case Block | ControlRegion | ControlBranch | ControlWhile | ControlFor | ControlSwitch | ControlTry | FixedRange: throw HxMacroBlockBoundary.missingSourceGroup;
		case Temporary | RuntimeTypeValue | RuntimeTypeTest | ArrayAppend | MapInsert:
			throw "lowered semantic expression cannot supply authored macro syntax";
	};
}
