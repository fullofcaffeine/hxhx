/** Select concrete loop-local types from iterable facts shared by typing and replay. */
function bindingTypes(binding:HxForBinding, iterable:HxExpr, type:TyType):Null<Array<TyType>> {
	switch iterable {
		case ERange(_, _):
			return switch binding {
				case Value(_): [TyType.fromHintText("Int")];
				case KeyValue(_, _): null;
			};
		case _:
	}
	final identity = type.getNominalIdentity();
	final path = identity == null ? type.getUnresolvedPath() : identity.getCanonicalName();
	final arguments = type.getTypeArguments();
	if ((path != "Array" && path != "haxe.Array") || arguments.length != 1 || arguments[0].hasUnknownComponent())
		return null;
	return switch binding {
		case Value(_): [arguments[0]];
		case KeyValue(_, _): [TyType.fromHintText("Int"), arguments[0]];
	};
}

/**
	Type a loop under its exact source-owned binding and control scope. Ordinary
	loops discard the returned body type; comprehensions use it as yield evidence.
	Both callers therefore record the same declarations for typed-body replay.
 */
function infer(input:{
	expression:HxExpr,
	scope:TyFunctionEnv,
	filePath:String,
	typeExpression:HxExpr->TyType,
	typeBody:HxExpr->TyType
}):{iterableType:TyType, bodyType:TyType} {
	return switch input.expression {
		case ESourceFor(binding, iterable, body, position):
			final iterableType = input.typeExpression(iterable);
			final types = bindingTypes(binding, iterable, iterableType);
			if (types == null)
				throw new TyperError(input.filePath, position, "source for requires a resolved iterable protocol");
			final controls = input.scope.requireControlScope();
			final target = controls.enter(Loop, TypedBodyFingerprint.forExpression(input.expression));
			input.scope.enterLexicalScope();
			final names = HxForBinding.names(binding);
			for (index in 0...names.length)
				input.scope.declareLocal(names[index], types[index], LoopVariable);
			final bodyType = input.typeBody(body);
			input.scope.exitLexicalScope();
			controls.exit(target);
			{iterableType: iterableType, bodyType: bodyType};
		case _: throw "source for inference requires an authored loop";
	};
}
