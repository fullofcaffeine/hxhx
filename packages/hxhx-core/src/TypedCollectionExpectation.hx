/**
	An empty literal has no element evidence, so its selected context determines
	whether it constructs an Array or Map. Only resolved collection declarations
	with complete argument shapes authorize this choice; source spelling does not.
 */
function isEmpty(expression:HxExpr):Bool {
	return switch expression {
		case EParenthesized(inner, _) | EPrivateAccess(inner, _): isEmpty(inner);
		case EArrayDecl(values): values.length == 0;
		case _: false;
	};
}

function select(expression:HxExpr, expected:Null<TyType>):Null<TyType> {
	if (expected == null)
		return null;
	if (!isEmpty(expression))
		return null;
	final type = expected.unwrapNull();
	final identity = type.getNominalIdentity();
	if (identity == null || type.hasUnknownComponent())
		return null;
	final arity = type.getTypeArguments().length;
	return switch identity.getCanonicalName() {
		case "Array" if (arity == 1): type;
		case "haxe.ds.Map" if (arity == 2): type;
		case _: null;
	};
}
