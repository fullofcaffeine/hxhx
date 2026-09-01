/**
	Aligns Stage3 source arguments with declaration-owned parameter positions.

	The policy inserts an omitted value only when the selected Haxe declaration
	marks that exact position optional or defaulted. It can skip optional
	positions when typing proves that the current source argument belongs to a
	later reachable parameter. It never skips a required position and reports the
	first required parameter left without a source argument.
**/
class EmitterCallArgPolicy {
	/**
		Build the fixed-parameter and rest boundary for one call.

		`preAppliedReceiverCount` is one only when the rendered callee already owns
		the instance receiver. `suppliedCount` then counts source-array entries only.
	**/
	public static function plan(signature:EmitterCallSig, suppliedCount:Int, preAppliedReceiverCount:Int,
			compatibility:(sourceIndex:Int, paramIndex:Int) -> EmitterCallArgCompatibility):EmitterCallArgPlanResult {
		if (signature == null)
			throw "Stage3 call argument planning requires a declaration signature";
		if (suppliedCount < 0)
			throw "Stage3 call argument planning requires a non-negative source argument count";
		if (preAppliedReceiverCount < 0 || preAppliedReceiverCount > 1 || preAppliedReceiverCount > signature.fixed)
			throw "Stage3 call argument planning received invalid pre-applied receiver accounting";
		if (preAppliedReceiverCount > 0 && !signature.needsReceiver)
			throw "Stage3 call argument planning cannot pre-apply a receiver to a static call";

		final sourceIndices = new Array<Null<Int>>();
		for (_ in 0...signature.fixed)
			sourceIndices.push(null);

		var sourceIndex = 0;
		var paramIndex = preAppliedReceiverCount;
		while (paramIndex < signature.fixed) {
			if (sourceIndex >= suppliedCount) {
				if (!isFillable(signature, paramIndex))
					return MissingRequired(paramIndex, paramName(signature, paramIndex));
				paramIndex += 1;
				continue;
			}

			final current = compatibility(sourceIndex, paramIndex);
			if (current == Incompatible && isFillable(signature, paramIndex)) {
				final later = laterCompatibleParam(signature, sourceIndex, paramIndex + 1, compatibility);
				if (later >= 0) {
					paramIndex = later;
					continue;
				}
			}

			sourceIndices[paramIndex] = sourceIndex;
			sourceIndex += 1;
			paramIndex += 1;
		}

		return Planned(new EmitterCallArgPlan(sourceIndices, preAppliedReceiverCount, sourceIndex));
	}

	static function laterCompatibleParam(signature:EmitterCallSig, sourceIndex:Int, start:Int,
			compatibility:(sourceIndex:Int, paramIndex:Int) -> EmitterCallArgCompatibility):Int {
		for (paramIndex in start...signature.fixed) {
			if (compatibility(sourceIndex, paramIndex) == Compatible)
				return paramIndex;
			if (!isFillable(signature, paramIndex))
				return -1;
		}
		return -1;
	}

	static function isFillable(signature:EmitterCallSig, paramIndex:Int):Bool {
		return signature.paramFillable != null
			&& paramIndex >= 0
			&& paramIndex < signature.paramFillable.length
			&& signature.paramFillable[paramIndex];
	}

	static function paramName(signature:EmitterCallSig, paramIndex:Int):String {
		if (signature.paramNames == null || paramIndex < 0 || paramIndex >= signature.paramNames.length)
			return "argument";
		final name = StringTools.trim(signature.paramNames[paramIndex]);
		return name.length == 0 ? "argument" : name;
	}
}
