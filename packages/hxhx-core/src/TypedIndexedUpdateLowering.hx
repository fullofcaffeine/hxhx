import TyIndexedUpdatePlan.TyIndexedUpdateStep;

/** Inputs the typed body builder supplies for one authored update occurrence. */
typedef TypedIndexedUpdateInput = {
	final expression:HxExpr;
	final type:TyType;
	final position:Null<HxPos>;
	final diagnosticPosition:HxPos;
	final environment:TyFunctionEnv;
	final resolver:TypedExprTypeResolver;
	final buildChild:HxExpr->TypedExpr;
};

/**
	Project one completed declared-index update into ordinary typed nodes.

	What a user sees: `values["x"]++`, `++values["x"]` and `values["x"] += 2` on a
	`Map` (or any abstract with `@:arrayAccess`/`@:op([])` helpers) now compile and run.
	Before this lowering the typer stopped with "Abstract indexed updates are not yet
	supported". The typed body receives one value block of compiler temporaries,
	calls to the exact selected getter/setter declarations, and the selected step, so
	a backend only chooses syntax. No backend sees a raw `a[i]` carrier update.

	Schedule (upstream Haxe 4.3.7, measured on the original Map workload):
	- `++`/`--`: save the key once (raw); call the getter on a freshly evaluated
	  receiver; compute the step; call the setter on a second evaluation of the
	  receiver (key conversions run at each call: "key;receiver;convert;receiver;convert;").
	  Postfix yields the saved raw getter value (including null/undefined on
	  JavaScript); prefix yields the setter's value.
	- compound: convert and save the key once, save the receiver once, read, evaluate
	  the right operand, apply the selected helper or primitive step, write; the
	  setter's value is the result.
	The block's static type is the setter's return type, as upstream types it.

	Explicit limits (diagnostics mention haxe_ocaml-rgmu4): a `++`/`--` receiver that
	declares locals or functions cannot be evaluated twice through the replayed
	lexical catalog; a selected compound helper must have a body and, when it is an
	instance method, must not be inline.
 */
class TypedIndexedUpdateLowering {
	final plan:TyIndexedUpdatePlan;
	final input:TypedIndexedUpdateInput;
	final allocator:TyCompilerTemporaryAllocator;
	final steps:Array<TypedExpr> = [];
	final receiverSource:HxExpr;
	final keySource:HxExpr;
	final rightSource:Null<HxExpr>;

	/** Null when the occurrence is not a completed declared-index update; the ordinary unary/compound node then applies. */
	public static function build(input:TypedIndexedUpdateInput):Null<TypedExpr> {
		final plan = input.resolver.indexedUpdate(input.expression, input.environment);
		return plan == null ? null : new TypedIndexedUpdateLowering(plan, input).lower();
	}

	function new(plan:TyIndexedUpdatePlan, input:TypedIndexedUpdateInput) {
		this.plan = plan;
		this.input = input;
		allocator = new TyCompilerTemporaryAllocator(input.environment.getOwnerIdentity(), "indexed-update-v1:" + plan.ordinal, "__hxhx_indexed_");
		final place = switch plan.query.getterSource {
			case EArrayAccess(receiver, key): {receiver: receiver, key: key};
			case _: throw "indexed update plan lost its getter place";
		};
		receiverSource = place.receiver;
		keySource = place.key;
		rightSource = switch plan.query.source {
			case EBinop(_, _, right): right;
			case _: null;
		};
	}

	function unsupported(message:String):TyperError
		return new TyperError("<typed-body>", input.diagnosticPosition, message + " (haxe_ocaml-rgmu4)");

	static function voidType():TyType
		return TyType.fromHintText("Void");

	function save(role:String, value:TypedExpr):TypedExpr {
		final binding = allocator.allocate(role, value.getType());
		steps.push(TypedExpr.temporary(binding.getSourceName(), binding.getType().getDisplay(), value, voidType(), value.getPosition(), binding));
		return TypedExpr.localRead(binding.getSourceName(), binding.getType(), value.getPosition(), binding);
	}

	/**
		A `++`/`--` receiver is evaluated once for the read and once for the write.
		Only receivers without declarations can be rebuilt twice from the same source.
	 */
	static function requireRepeatable(expression:HxExpr):Bool {
		return switch expression {
			case EIdent(_) | EThis | ENull | EBool(_) | EString(_) | EInt(_) | EFloat(_) | EEnumValue(_): true;
			case EField(inner, _) | ENullSafeField(inner, _) | EParenthesized(inner, _) | EPrivateAccess(inner, _) | ECast(inner, _) | ECheckType(inner, _) |
				EUntyped(inner) | EUnop(_, _, inner): requireRepeatable(inner);
			case EArrayAccess(left, right) | EBinop(_, left, right): requireRepeatable(left) && requireRepeatable(right);
			case ETernary(condition, whenTrue, whenFalse): requireRepeatable(condition) && requireRepeatable(whenTrue) && requireRepeatable(whenFalse);
			case ECall(callee, arguments): requireRepeatable(callee) && arguments.filter(argument -> !requireRepeatable(argument)).length == 0;
			case ENew(_, arguments) | EArrayDecl(arguments): arguments.filter(argument -> !requireRepeatable(argument)).length == 0;
			case EAnon(_, values): values.filter(value -> !requireRepeatable(value)).length == 0;
			case _: false;
		};
	}

	/**
		Call one selected indexed helper with substituted operands.
		Operands that already have their expected type (a converted compound key) are
		passed as they are; others receive the retained implicit conversion and value
		conversion, as an ordinary indexed call does. The setter's value operand is
		never converted here: its executable conversions are the plan's retained
		place/setter conversions, and an admitted value stays raw.
	 */
	function helperCall(declaration:TyDeclarationInfo, resolution:TypedCallResolution, sources:Array<HxExpr>, operand:HxExpr->TypedExpr,
			valueSource:Null<HxExpr>, resultType:TyType):TypedExpr {
		final expected = resolution.getExpectedArguments();
		final conversions = resolution.getArgumentConversions();
		if (expected.length != sources.length || (conversions.length != 0 && conversions.length != sources.length))
			throw "indexed helper call lost its selected argument contexts";
		final arguments = [
			for (offset in 0...sources.length) {
				final value = operand(sources[offset]);
				if (sources[offset] == valueSource
					|| expected[offset].isUnknown()
					|| value.getType().getSemanticKey() == expected[offset].getSemanticKey()) value; else {
					final converted = conversions.length == 0 || conversions[offset] == null ? value : conversions[offset].apply(value);
					input.resolver.convertValue(converted, expected[offset]);
				}
			}
		];
		final name = declaration.getSignature().getName();
		final callable = TyType.functionType(expected, resultType);
		final callee = declaration.getIsStatic() ? TypedExpr.staticMethodRead(name, declaration, callable, input.position,
			true) : TypedExpr.instanceMethodRead(operand(receiverSource), name, declaration, callable, input.position);
		final call = TypedExpr.call(callee, arguments, declaration, resultType, input.position, declaration.getIsStatic());
		return call.withNamedArguments(resolution.getNamedArguments().publish(arguments, resultType));
	}

	function rightOperand():TypedExpr
		return rightSource == null ? TypedExpr.intLiteral(1, TyType.fromHintText("Int"), input.position) : input.buildChild(rightSource);

	/** Representation view between an abstract value and its numeric storage; no runtime operation. */
	function view(value:TypedExpr, type:TyType):TypedExpr
		return value.getType()
			.getSemanticKey() == type.getSemanticKey() ? value : TypedExpr.castValue(value, type.getCanonicalDisplay(), type, input.position, true);

	function computed(old:TypedExpr):TypedExpr {
		return switch plan.step {
			case Primitive(op, result):
				TypedExpr.binary(op, old, rightOperand(), result, input.position);
			case StorageView(op, storage, result):
				final viewType = result.isNullable() ? TyType.nullable(storage) : storage;
				view(TypedExpr.binary(op, view(old, viewType), rightOperand(), viewType, input.position), result);
			case Selected(binding, left, right, result):
				selectedCall(binding, left == null ? old : left.apply(old), right == null ? rightOperand() : right.apply(rightOperand()), result);
		};
	}

	/** The exact selected operator declaration; source operands are already evaluated (getter first), so orientation only orders the call. */
	function selectedCall(binding:TyBoundAbstractBinaryOperator, left:TypedExpr, right:TypedExpr, result:TyType):TypedExpr {
		final info = binding.getOperatorInfo();
		final declaration = info.getDeclaration();
		final key = declaration.getIdentity().getCanonicalKey();
		if (!declaration.getHasBody())
			throw unsupported("Indexed compound update cannot use the bodyless operator helper " + key);
		if (!declaration.getIsStatic() && declaration.getIsInline())
			throw unsupported("Indexed compound update cannot expand the inline instance operator helper " + key);
		final ordered = binding.getReverseArguments() ? [right, left] : [left, right];
		final name = declaration.getSignature().getName();
		if (declaration.getIsStatic()) {
			final callee = TypedExpr.staticMethodRead(name, declaration, TyType.functionType([info.getLeftType(), info.getRightType()], result),
				input.position, true);
			return TypedExpr.call(callee, ordered, declaration, result, input.position, true);
		}
		final callee = TypedExpr.instanceMethodRead(ordered[0], name, declaration, TyType.functionType([info.getRightType()], result), input.position);
		return TypedExpr.call(callee, [ordered[1]], declaration, result, input.position);
	}

	/** Apply only the retained executable conversions between the computed value, the place and the setter parameter. */
	function written(value:TypedExpr):TypedExpr {
		final placed = plan.placeConversion == null ? value : plan.placeConversion.apply(value);
		return plan.setterConversion == null ? placed : plan.setterConversion.apply(placed);
	}

	function lower():TypedExpr {
		final unary = rightSource == null;
		final getter = input.resolver.indexedAccess(plan.query.getterSource, input.diagnosticPosition, input.environment);
		if (getter == null || getter.call == null || getter.binding.declaration == null)
			throw "indexed update lost its selected getter call";
		if (unary && !requireRepeatable(receiverSource))
			throw unsupported("Indexed increment/decrement receiver declares locals or functions and cannot be evaluated twice");
		final keyValue = input.buildChild(keySource);
		final key = if (unary) {
			save("key", keyValue);
		} else {
			final sources = getter.binding.getArguments();
			final expected = getter.call.getExpectedArguments()[sources.indexOf(keySource)];
			final plans = getter.call.getArgumentConversions();
			final converted = plans.length == 0
				|| plans[sources.indexOf(keySource)] == null ? keyValue : plans[sources.indexOf(keySource)].apply(keyValue);
			save("key", expected.isUnknown() ? converted : input.resolver.convertValue(converted, expected));
		}
		final receiver = unary ? null : save("receiver", input.buildChild(receiverSource));
		function operand(source:HxExpr):TypedExpr {
			if (source == keySource)
				return key;
			if (source == receiverSource)
				return receiver == null ? input.buildChild(receiverSource) : receiver;
			throw "indexed update call has a foreign operand";
		}
		final old = save("old", helperCall(getter.binding.declaration, getter.call, getter.binding.getArguments(), operand, null, plan.getterType));
		final after = save("after", computed(old));
		final valueSource = plan.query.setterInputSource;
		final write = helperCall(plan.setterDeclaration, plan.setterCall, plan.setterSources,
			source -> source == valueSource ? written(after) : operand(source), valueSource, plan.staticType);
		steps.push(write);
		switch plan.payload {
			case OldGetter:
				steps.push(old);
			case SetterValue:
		}
		return TypedExpr.block(steps, plan.staticType, input.position);
	}
}
