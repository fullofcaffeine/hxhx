/** A valid direct iterator takes precedence; otherwise select the iterable's factory. */
function selectProtocol(source:HxExpr, resolve:HxExpr->TyType, owner:String, kind:TyIteratorProtocolSource.TyIteratorProtocolKind):TyIteratorProtocolSource {
	final hasNext = resolve(EField(source, "hasNext"));
	final next = resolve(EField(source, "next"));
	if (hasNext.isFunction()
		&& hasNext.getFunctionArguments().length == 0
		&& hasNext.getFunctionReturn().getSemanticKey() == "primitive:Bool"
		&& next.isFunction()
		&& next.getFunctionArguments().length == 0) {
		final direct = new TyIteratorProtocolSource(source, owner, kind, true);
		if ((direct.key == null || !resolve(direct.key).hasUnknownComponent()) && !resolve(direct.value).hasUnknownComponent())
			return direct;
	}
	return new TyIteratorProtocolSource(source, owner, kind);
}

/** Report a missing factory only when its exact receiver and member query establish that absence. */
function protocolDiagnostic(type:TyType, protocol:Null<TyIteratorProtocolSource>, resolve:HxExpr->TyType, fallback:String):String {
	if (!type.hasUnknownComponent() && !type.isDynamic() && protocol != null && protocol.factory != null && resolve(protocol.factory).isUnknown())
		return type.getDisplay() + " has no field " + (protocol.kind == Values ? "iterator" : "keyValueIterator");
	return fallback;
}

/** Select concrete loop-local types from iterable facts shared by typing and replay. */
function bindingTypes(binding:HxForBinding, iterable:HxExpr, type:TyType, ?resolve:HxExpr->TyType,
		?protocol:() -> TyIteratorProtocolSource):Null<Array<TyType>> {
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
		// Type queries select calls once; lowering later saves acquisition and
		// executes each next operation exactly once, including for plain values.
		final selected = protocol();
		final condition = resolve(selected.condition);
		final value = resolve(selected.value);
		if (condition.getSemanticKey() != "primitive:Bool" || value.hasUnknownComponent())
			return null;
		return switch binding {
			case KeyValue(_, _):
				if (selected.kind != KeyValues || selected.key == null)
					throw "key/value loop lost its selected iterator protocol";
				final key = resolve(selected.key);
				key.hasUnknownComponent() ? null : [key, value];
			case Value(_):
				if (selected.kind != Values)
					throw "value loop lost its selected iterator protocol";
				[value];
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
					.iteratorProtocolSource(iterable,
						source -> selectProtocol(source, inferProtocol, input.scope.getOwnerIdentity(), binding.match(Value(_)) ? Values : KeyValues)));
			if (types == null) {
				final fallback = "source for requires a resolved iterable protocol";
				final message = protocolDiagnostic(iterableType,
					iterable.match(ERange(_, _)) ? null : input.scope.getInference().iteratorProtocolSource(iterable), inferProtocol, fallback);
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
