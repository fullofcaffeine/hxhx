package backend.vm;

/**
	Consume the exact Array append selected by shared comprehension lowering.
	The ordinary authored push method owns growth and alias-visible mutation.
	No source-name match or reconstructed call may borrow this operation's types.
 */
function requireAppend(context:NekoEmitContext, expression:HxExpr):Void {
	final occurrence = switch context.currentExecutable {
		case FunctionBody(selected): selected.body.requireCollectionControl(expression);
		case FieldInitializer(selected): selected.requireCollectionControl(expression);
		case null: throw "Neko collection append requires its exact executable owner";
	};
	switch occurrence.operation {
		case Append(type, value):
			final concrete = TyAliasExpansion.revealNonNullable(type);
			final identity = concrete.getNominalIdentity();
			final arguments = concrete.getTypeArguments();
			if (identity == null
				|| identity.getCanonicalName() != "Array"
				|| arguments.length != 1
				|| arguments[0].getSemanticKey() != value.getSemanticKey())
				throw "Neko append lost its exact Array element conversion";
		case _:
			throw "Neko append requires its selected collection operation";
	}
}

/** Evaluate the original container before the converted element, then dispatch its provider method. */
function renderAppend(context:NekoEmitContext, expression:HxExpr, emit:HxExpr->String):String {
	requireAppend(context, expression);
	return switch expression {
		case ELoweredControl(ArrayAppend, "", [array, value], _):
			NekoFieldCall.render(context.typedProgram, emit(array), "push", [emit(value)]);
		case _: throw "Neko append lost its checked operand layout";
	};
}
