import TyCallAlignment.TyCallAlignmentResult;
import TyCallAlignment.TyCallOperandKind;

/** Query source-aware assignment without changing inference or emitting conversions. */
private function compatible(index:TyperIndex, expression:HxExpr, expected:TyType, actual:TyType, spread:Bool):TyCallArgumentCompatibility {
	if (spread)
		return TyAssignmentCompatibility.classifyRestSpread(expected, actual);
	if (!TyStructuralArgument.literalFits(expression, expected))
		return Incompatible;
	final structural = TyStructuralArgument.compatibility(index, expected, actual);
	if (structural != null)
		return structural;
	final basic = TyAssignmentCompatibility.classify(expected, actual, Unchecked);
	if (basic != Unknown || expected.hasUnknownComponent() || actual.hasUnknownComponent())
		return basic;
	if (TyEnumValueCompatibility.accepts(index, expected, actual))
		return Compatible;
	final target = expected.unwrapNull();
	final identity = target.getNominalIdentity();
	final ancestor = identity == null ? null : TyNominalAncestor.view(index, actual.unwrapNull(), identity);
	if (ancestor != null && ancestor.getSemanticKey() == target.getSemanticKey())
		return Compatible;
	// A declared abstract header can admit this same stored value. Matching an
	// abstract's backing type alone is insufficient: the shared conversion owner
	// must prove the declared direction and unchanged representation. Executable
	// conversion methods still need a separate typed call and remain unproved here.
	final conversion = TyImplicitConversionPlan.select(index, target, actual.unwrapNull());
	return conversion != null && conversion.isRepresentationPreservingAbstractConversion() ? Compatible : Unknown;
}

/** Check a selected signature without publishing a binding or changing the source operands. */
function align(signature:TyCallableSignature, arguments:Array<HxExpr>, types:Array<TyType>, index:TyperIndex):TyCallAlignmentResult {
	if (arguments.length != types.length)
		throw "call alignment requires one type per operand";
	final kinds:Array<TyCallOperandKind> = [
		for (argument in arguments)
			argument.match(ECall(EIdent("__hxhx_spread"), [_])) ? Spread : Value
	];
	final parameters = signature.getParameters();
	return TyCallAlignment.align(parameters, kinds,
		(source, parameter, spread) -> compatible(index, arguments[source], parameters[parameter].type, types[source], spread));
}

/** Freeze a captured call only after its shared variables have their final types. */
function publish(signature:TyCallableSignature, arguments:Array<HxExpr>, types:Array<TyType>, index:TyperIndex):TyCallArgumentBinding {
	final kinds:Array<TyCallOperandKind> = [
		for (argument in arguments)
			argument.match(ECall(EIdent("__hxhx_spread"), [_])) ? Spread : Value
	];
	return switch align(signature, arguments, types, index) {
		case Aligned(slots): new TyCallArgumentBinding(signature, types, kinds, slots, Unchecked);
		case Rejected(failure): throw "cannot publish captured callback arguments: " + TyCallValidation.describeFailure(failure, signature, types, kinds);
	};
}

/** Validate converted operands against the already selected slots; conversions must never reselect an optional parameter. */
function publishSelected(signature:TyCallableSignature, arguments:Array<HxExpr>, types:Array<TyType>, index:TyperIndex,
		order:TyMethodArgumentOrder):TyCallArgumentBinding {
	return publishSlots(signature, arguments, types, index, order.getSlots());
}

/** Final callback publication checks retained slots after inference, without selecting a different optional argument. */
function publishSlots(signature:TyCallableSignature, arguments:Array<HxExpr>, types:Array<TyType>, index:TyperIndex,
		slots:Array<TyCallAlignment.TyCallArgumentSlot>):TyCallArgumentBinding {
	if (arguments.length != types.length)
		throw "selected call requires one final type per source operand";
	final parameters = signature.getParameters();
	if (slots.length != parameters.length)
		throw "selected call order differs from its final signature";
	final kinds:Array<TyCallOperandKind> = [
		for (argument in arguments)
			argument.match(ECall(EIdent("__hxhx_spread"), [_])) ? Spread : Value
	];
	var next = 0;
	function check(source:Int, parameter:Int, spread:Bool):Void {
		if (source != next || source >= types.length || (kinds[source] == Spread) != spread)
			throw "selected call changed source order or spread shape";
		next++;
		if (compatible(index, arguments[source], parameters[parameter].type, types[source], spread) != Compatible)
			throw "selected call conversion does not satisfy its retained parameter: "
				+ types[source].getSemanticKey() + " -> " + parameters[parameter].type.getSemanticKey();
	}
	for (parameter in 0...slots.length)
		switch slots[parameter] {
			case Omitted:
				if (!parameters[parameter].isOptional || parameters[parameter].isRest)
					throw "selected call omitted a required parameter";
			case Supplied(source):
				if (parameters[parameter].isRest)
					throw "selected call lost its rest shape";
				check(source, parameter, false);
			case RestElements(sources):
				if (!parameters[parameter].isRest)
					throw "selected call invented a rest parameter";
				for (source in sources)
					check(source, parameter, false);
			case RestSpread(source):
				if (!parameters[parameter].isRest)
					throw "selected call invented a spread parameter";
				check(source, parameter, true);
		}
	if (next != types.length)
		throw "selected call omitted a supplied operand";
	return new TyCallArgumentBinding(signature, types, kinds, slots, Unchecked);
}

/**
	Use a selected callback's parameters to finish existing argument inference.
	Optional alignment probes isolated solver forks. Only the complete selected
	alignment may commit; source expressions are never inferred a second time.
 */
function resolve(signature:TyCallableSignature, arguments:Array<HxExpr>, types:Array<TyType>, kinds:Array<TyCallOperandKind>, environment:TyFunctionEnv,
		index:TyperIndex, ?callee:HxExpr):TyCallAlignmentResult {
	final inference = environment.getInference();
	final retained = callee == null ? null : inference.callbackBinding(callee);
	if (retained != null) {
		retained.assertCurrent(signature.getFunctionType(), types, kinds);
		return Aligned(retained.getSlots());
	}
	final parameters = signature.getParameters();
	final sources = [
		for (argument in arguments)
			switch argument {
				case ECall(EIdent("__hxhx_spread"), [container]):
					container;
				case _:
					argument;
			}
	];
	function context(source:Int, parameter:Int, spread:Bool):Null<TyType> {
		final expected = parameters[parameter].type;
		if (!spread)
			return expected;
		final identity = types[source].getNominalIdentity();
		if (identity == null
			|| types[source].getTypeArguments().length != 1
			|| (identity.getCanonicalName() != "Array" && identity.getCanonicalName() != "haxe.Rest"))
			return null;
		return TyType.nominal(identity, [expected]);
	}
	final aligned = TyCallAlignment.align(parameters, kinds, (source, parameter, spread) -> {
		final original = compatible(index, sources[source], parameters[parameter].type, types[source], spread);
		if (!types[source].hasUnknownComponent() || !inference.canReceiveContext(sources[source], environment))
			return original;
		final expected = context(source, parameter, spread);
		if (expected == null || expected.isDynamic() || expected.hasUnknownComponent())
			return original;
		final trial = inference.fork();
		if (!trial.constrain([sources[source]], [expected], environment, index))
			return Incompatible;
		return compatible(index, sources[source], parameters[parameter].type, trial.callbackContextType(sources[source], types[source], environment), spread);
	});
	return switch aligned {
		case Rejected(_): aligned;
		case Aligned(slots):
			final selectedSources = new Array<HxExpr>();
			final selectedTypes = new Array<TyType>();
			final trial = inference.fork();
			var failure:Null<TyCallAlignment.TyCallAlignmentFailure> = null;
			function select(source:Int, parameter:Int, spread:Bool):Void {
				if (failure != null || !types[source].hasUnknownComponent())
					return;
				final expected = context(source, parameter, spread);
				if (expected == null)
					return;
				if (!trial.constrain([sources[source]], [expected], environment, index)) {
					failure = IncompatibleArgument(source, parameter);
					return;
				}
				selectedSources.push(sources[source]);
				selectedTypes.push(expected);
			}
			for (parameter in 0...slots.length)
				switch slots[parameter] {
					case Omitted:
					case Supplied(source): select(source, parameter, false);
					case RestElements(sources): for (source in sources)
							select(source, parameter, false);
					case RestSpread(source): select(source, parameter, true);
				}
			if (failure != null) {
				Rejected(failure);
			} else {
				final solved = [
					for (source in 0...sources.length)
						trial.callbackContextType(sources[source], types[source], environment)
				];
				// Validate the selected slots, without repeating optional selection under a different policy.
				function check(source:Int, parameter:Int, spread:Bool):Void {
					if (failure == null)
						switch compatible(index, sources[source], parameters[parameter].type, solved[source], spread) {
							case Compatible:
							case Incompatible:
								failure = IncompatibleArgument(source, parameter);
							case Unknown:
								failure = UnprovedArgument(source, parameter);
						}
				}
				for (parameter in 0...slots.length)
					switch slots[parameter] {
						case Omitted:
						case Supplied(source): check(source, parameter, false);
						case RestElements(sources): for (source in sources)
								check(source, parameter, false);
						case RestSpread(source): check(source, parameter, true);
					}
				final checked:TyCallAlignmentResult = failure == null ? Aligned(slots) : Rejected(failure);
				switch checked {
					case Rejected(_): checked;
					case Aligned(_):
						if (!inference.constrain(selectedSources, selectedTypes, environment, index))
							throw "callback argument constraints changed after isolated validation";
						if (callee != null)
							inference.recordCallbackAlignment(callee, signature, arguments, types, slots, environment, index);
						for (source in 0...sources.length)
							types[source] = trial.expressionType(sources[source], types[source], environment);
						checked;
				}
			}
	};
}
