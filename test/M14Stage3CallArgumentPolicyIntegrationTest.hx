/**
	Proves the declaration-driven Stage3 call alignment contract without target
	emission noise.

	The cases cover required positions, trailing omission, type-directed optional
	skipping, required barriers, pre-applied and source-supplied receivers, and
	rest-array boundaries.
**/
class M14Stage3CallArgumentPolicyIntegrationTest {
	static function signature(names:Array<String>, fillable:Array<Bool>, ?needsReceiver:Bool = false, ?hasRest:Bool = false):EmitterCallSig {
		final fixed = names.length - (hasRest ? 1 : 0);
		var required = 0;
		for (index in 0...fixed)
			if (!fillable[index])
				required += 1;
		return {
			expected: names.length,
			required: required,
			fixed: fixed,
			hasRest: hasRest,
			needsReceiver: needsReceiver,
			paramNames: names,
			paramFillable: fillable,
			paramTypeHints: [for (_ in names) "Dynamic"],
			resultTypeHint: "Void"
		};
	}

	static function assertEquals<T>(expected:T, actual:T, label:String):Void {
		if (expected != actual)
			throw label + ": expected " + Std.string(expected) + ", got " + Std.string(actual);
	}

	static function assertSlots(expected:Array<Null<Int>>, plan:EmitterCallArgPlan, label:String):Void {
		final actual = plan.getFixedSourceIndices();
		assertEquals(expected.length, actual.length, label + " length");
		for (index in 0...expected.length)
			assertEquals(expected[index], actual[index], label + " slot " + index);
	}

	static function expectPlan(result:EmitterCallArgPlanResult, label:String):EmitterCallArgPlan {
		return switch (result) {
			case Planned(plan):
				plan;
			case MissingRequired(index, name):
				throw label + ": unexpected missing parameter " + index + " (`" + name + "`)";
		};
	}

	static function expectMissing(result:EmitterCallArgPlanResult, expectedIndex:Int, expectedName:String, label:String):Void {
		switch (result) {
			case Planned(_):
				throw label + ": expected a missing-required result";
			case MissingRequired(index, name):
				assertEquals(expectedIndex, index, label + " index");
				assertEquals(expectedName, name, label + " name");
		}
	}

	static function alwaysCompatible(_sourceIndex:Int, _paramIndex:Int):EmitterCallArgCompatibility
		return Compatible;

	static function main():Void {
		final required = signature(["first", "second"], [false, false]);
		expectMissing(EmitterCallArgPolicy.plan(required, 1, 0, alwaysCompatible), 1, "second", "missing required argument");

		final trailingOptional = signature(["value", "position"], [false, true]);
		final trailingPlan = expectPlan(EmitterCallArgPolicy.plan(trailingOptional, 1, 0, alwaysCompatible), "trailing optional");
		assertSlots([0, null], trailingPlan, "trailing optional");
		assertEquals(1, trailingPlan.getRestSourceStart(), "trailing optional source consumption");

		final shifted = signature(["account", "repository", "branch", "sourcePath", "useRetry", "alternateName"], [false, false, true, true, true, true]);
		final shiftedPlan = expectPlan(EmitterCallArgPolicy.plan(shifted, 3, 0, (sourceIndex, paramIndex) -> {
			if (sourceIndex < 2)
				return sourceIndex == paramIndex ? Compatible : Incompatible;
			return paramIndex == 4 ? Compatible : Incompatible;
		}), "optional skipping");
		assertSlots([0, 1, null, null, 2, null], shiftedPlan, "optional skipping");

		final requiredBarrier = signature(["optional", "required", "laterOptional"], [true, false, true]);
		final barrierResult = EmitterCallArgPolicy.plan(requiredBarrier, 1, 0, (_sourceIndex, paramIndex) -> paramIndex == 2 ? Compatible : Incompatible);
		expectMissing(barrierResult, 1, "required", "required skip barrier");

		final receiver = signature(["this", "value", "position"], [false, false, true], true);
		final preApplied = expectPlan(EmitterCallArgPolicy.plan(receiver, 1, 1, alwaysCompatible), "pre-applied receiver");
		assertSlots([null, 0, null], preApplied, "pre-applied receiver");
		assertEquals(1, preApplied.getFirstRenderedParam(), "pre-applied receiver boundary");

		final suppliedReceiver = expectPlan(EmitterCallArgPolicy.plan(receiver, 2, 0, alwaysCompatible), "source-supplied receiver");
		assertSlots([0, 1, null], suppliedReceiver, "source-supplied receiver");
		assertEquals(0, suppliedReceiver.getFirstRenderedParam(), "source-supplied receiver boundary");
		expectMissing(EmitterCallArgPolicy.plan(receiver, 0, 0, alwaysCompatible), 0, "this", "missing receiver");
		final receiverWithRequiredArgs = signature(["this", "first", "second"], [false, false, false], true);
		expectMissing(EmitterCallArgPolicy.plan(receiverWithRequiredArgs, 2, 0, alwaysCompatible), 2, "second",
			"source-supplied receiver with missing argument");

		final rest = signature(["required", "rest"], [false, false], false, true);
		final restPlan = expectPlan(EmitterCallArgPolicy.plan(rest, 3, 0, alwaysCompatible), "rest arguments");
		assertSlots([0], restPlan, "rest fixed argument");
		assertEquals(1, restPlan.getRestSourceStart(), "rest source boundary");
		expectMissing(EmitterCallArgPolicy.plan(rest, 0, 0, alwaysCompatible), 0, "required", "required argument before rest");

		final optionalBeforeRest = signature(["label", "count", "rest"], [true, false, false], false, true);
		final optionalRestPlan = expectPlan(EmitterCallArgPolicy.plan(optionalBeforeRest, 3, 0,
			(sourceIndex, paramIndex) -> sourceIndex == 0 && paramIndex == 1 ? Compatible : Incompatible),
			"optional before rest");
		assertSlots([null, 0], optionalRestPlan, "optional before rest");
		assertEquals(1, optionalRestPlan.getRestSourceStart(), "optional before rest source boundary");
	}
}
