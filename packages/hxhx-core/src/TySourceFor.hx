/** A valid direct iterator takes precedence; otherwise select the iterable's factory. */
function selectProtocol(source:HxExpr, resolve:HxExpr->TyType, owner:String):TyKeyValueProtocolSource {
	final hasNext = resolve(EField(source, "hasNext"));
	final next = resolve(EField(source, "next"));
	if (hasNext.isFunction()
		&& hasNext.getFunctionArguments().length == 0
		&& hasNext.getFunctionReturn().getSemanticKey() == "primitive:Bool"
		&& next.isFunction()
		&& next.getFunctionArguments().length == 0) {
		final direct = new TyKeyValueProtocolSource(source, owner, true);
		if (!resolve(direct.key).hasUnknownComponent() && !resolve(direct.value).hasUnknownComponent())
			return direct;
	}
	return new TyKeyValueProtocolSource(source, owner);
}

/** Report a missing factory only when its exact receiver and member query establish that absence. */
function protocolDiagnostic(type:TyType, protocol:Null<TyKeyValueProtocolSource>, resolve:HxExpr->TyType, fallback:String):String {
	if (!type.hasUnknownComponent() && !type.isDynamic() && protocol != null && protocol.factory != null && resolve(protocol.factory).isUnknown())
		return type.getDisplay() + " has no field keyValueIterator";
	return fallback;
}

/** Select concrete loop-local types from iterable facts shared by typing and replay. */
function bindingTypes(binding:HxForBinding, iterable:HxExpr, type:TyType, ?resolve:HxExpr->TyType,
		?protocol:() -> TyKeyValueProtocolSource):Null<Array<TyType>> {
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
	if ((path != "Array" && path != "haxe.Array") || arguments.length != 1 || arguments[0].hasUnknownComponent()) {
		if (resolve == null || protocol == null)
			return null;
		return switch binding {
			case KeyValue(_, _):
				// These are type queries only. Executable acquisition and next calls
				// must later be retained once in the typed loop's protocol lowering.
				final selected = protocol();
				final condition = resolve(selected.condition);
				final key = resolve(selected.key);
				final value = resolve(selected.value);
				if (condition.getSemanticKey() != "primitive:Bool" || key.hasUnknownComponent() || value.hasUnknownComponent())
					return null;
				[key, value];
			case Value(_): null;
		};
	}
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
			final inferProtocol = expression -> input.scope.withProtocolSource(iterable, iterableType, () -> input.typeExpression(expression));
			final types = bindingTypes(binding, iterable, iterableType, inferProtocol,
				() -> input.scope.getInference()
					.keyValueProtocolSource(iterable, source -> selectProtocol(source, inferProtocol, input.scope.getOwnerIdentity())));
			if (types == null) {
				final fallback = "source for requires a resolved iterable protocol";
				final message = switch binding {
					case KeyValue(_, _):
						protocolDiagnostic(iterableType, iterable.match(ERange(_, _)) ? null : input.scope.getInference().keyValueProtocolSource(iterable),
							inferProtocol, fallback);
					case Value(_): fallback;
				};
				throw new TyperError(input.filePath, position, message);
			}
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
