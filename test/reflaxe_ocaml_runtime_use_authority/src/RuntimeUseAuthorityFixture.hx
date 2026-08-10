import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlModuleItem;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Proves that generated private-runtime names still match their sealed plans.

	The key regression uses two planned calls with the same printed OCaml name.
	A module-level scan sees `HxArray.set` in both the valid U1/U2 tree and the
	corrupted U2/U2 tree. The occurrence checker must distinguish the use IDs,
	reject the duplicate, and report the missing planned use before printing.
**/
class RuntimeUseAuthorityFixture {
	static inline final PLAN_REVISION = "plan:array-assign:v1";
	static inline final PROFILE = "portable";

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function expectFailure(label:String, expectedMessage:String, action:Void->Void):Void {
		var failed = false;
		try {
			action();
		} catch (error:Dynamic) {
			failed = true;
			final message = Std.string(error);
			if (!message.contains(expectedMessage))
				throw '$label failed with an unexpected message: $message';
		}
		if (!failed)
			throw '$label should have failed.';
	}

	static function occurrence(id:String, order:Int, ?symbol:String = "HxArray.set", ?domain:OcamlRuntimeUseDomain, ?planRevision:String = PLAN_REVISION,
			?ownerId:String = "place:array-simple-assignment"):OcamlRuntimeUseOccurrence {
		return {
			id: id,
			planRevision: planRevision,
			ownerId: ownerId,
			requirementId: "place:array:runtime:haxe-array-element-set",
			domain: domain == null ? OcamlRuntimeUseDomain.ExpressionIdentifier : domain,
			exactSymbol: symbol,
			role: "store",
			order: order,
			source: {
				file: "src/Main.hx",
				min: 20,
				max: 31
			},
			profileEligibility: ["metal", "portable"],
			cardinality: 1
		};
	}

	static function requirement():OcamlRuntimeRequirement {
		return OcamlRuntimeRequirementLedger.requirementForPlaceCapability("place:array-simple-assignment", "place:array", "place:array",
			{file: "src/Main.hx", min: 20, max: 31}, "Int", "place:array:runtime:haxe-array-element-set");
	}

	static function authority(occurrences:Array<OcamlRuntimeUseOccurrence>, ?profile:String = PROFILE,
			?requirements:Array<OcamlRuntimeRequirement>):OcamlRuntimeUseAuthority {
		return new OcamlRuntimeUseAuthority(PLAN_REVISION, profile, requirements == null ? [requirement()] : requirements, occurrences);
	}

	static function validSameSymbolUses():Void {
		final checker = authority([occurrence("U1", 0), occurrence("U2", 1)]);
		final u1 = checker.expressionIdentifier("U1", PLAN_REVISION, "HxArray.set");
		final u2 = checker.expressionIdentifier("U2", PLAN_REVISION, "HxArray.set");
		final receipts = checker.receiptsSorted();
		assertTrue(receipts.length == 2 && receipts[0].id == "U1" && receipts[1].id == "U2",
			"Construction receipts should preserve the plan's owner-local order.");
		checker.reconcileExpression(OcamlExpr.ESeq([OcamlExpr.ERuntimeIdent(u1), OcamlExpr.ERuntimeIdent(u2)]));
	}

	static function duplicateSameSymbolUseFails():Void {
		final checker = authority([occurrence("U1", 0), occurrence("U2", 1)]);
		final u2 = checker.expressionIdentifier("U2", PLAN_REVISION, "HxArray.set");
		expectFailure("duplicate U2 and missing U1", "duplicate runtime use U2; missing runtime use U1",
			() -> checker.reconcileExpression(OcamlExpr.ESeq([OcamlExpr.ERuntimeIdent(u2), OcamlExpr.ERuntimeIdent(u2)])));
	}

	/**
		Proves that local success cannot be reused as permission for two outputs.

		The first check accepts the one expression selected by the lowering plan.
		The final check sees that compiler assembly placed that same expression in
		two bindings, so it must reject the second output occurrence before print.
	**/
	static function duplicatedReconciledSubtreeFailsFinalOutput():Void {
		final finalOutput = new OcamlFinalRuntimeUseAuthority();
		finalOutput.beginProgram("program:runtime-use-fixture:v1", PROFILE);
		final checker = new OcamlRuntimeUseAuthority(PLAN_REVISION, PROFILE, [requirement()], [occurrence("U1", 0)], finalOutput);
		final reference = checker.expressionIdentifier("U1", PLAN_REVISION, "HxArray.set");
		final expression = OcamlExpr.ERuntimeIdent(reference);
		checker.reconcileExpression(expression);

		expectFailure("duplicated final subtree", "duplicate final runtime use U1", () -> finalOutput.observeModuleItems([
			OcamlModuleItem.ILet([{name: "first", expr: expression}, {name: "second", expr: expression}], false)
		]));
	}

	static function finalOutputContract():Void {
		final validOutput = new OcamlFinalRuntimeUseAuthority();
		validOutput.beginProgram("program:runtime-use-fixture:valid", PROFILE);
		final validAuthority = new OcamlRuntimeUseAuthority(PLAN_REVISION, PROFILE, [requirement()], [occurrence("U1", 0), occurrence("U2", 1)], validOutput);
		final validU1 = OcamlExpr.ERuntimeIdent(validAuthority.expressionIdentifier("U1", PLAN_REVISION, "HxArray.set"));
		final validU2 = OcamlExpr.ERuntimeIdent(validAuthority.expressionIdentifier("U2", PLAN_REVISION, "HxArray.set"));
		validAuthority.reconcileExpression(OcamlExpr.ESeq([validU1, validU2]));
		validOutput.observeModuleItems([
			OcamlModuleItem.ILet([{name: "first", expr: validU1}, {name: "second", expr: validU2}], false)
		]);
		validOutput.finishProgram();

		final repeatedPlanOutput = new OcamlFinalRuntimeUseAuthority();
		repeatedPlanOutput.beginProgram("program:runtime-use-fixture:repeated-plan", PROFILE);
		final firstRepeatedPlan = new OcamlRuntimeUseAuthority(PLAN_REVISION, PROFILE, [requirement()], [occurrence("U1", 0)], repeatedPlanOutput);
		final firstRepeatedReference = firstRepeatedPlan.expressionIdentifier("U1", PLAN_REVISION, "HxArray.set");
		firstRepeatedPlan.reconcileExpression(OcamlExpr.ERuntimeIdent(firstRepeatedReference));
		final secondRepeatedPlan = new OcamlRuntimeUseAuthority(PLAN_REVISION, PROFILE, [requirement()], [occurrence("U1", 0)], repeatedPlanOutput);
		final secondRepeatedReference = secondRepeatedPlan.expressionIdentifier("U1", PLAN_REVISION, "HxArray.set");
		secondRepeatedPlan.reconcileExpression(OcamlExpr.ERuntimeIdent(secondRepeatedReference));
		final conflictingPlan = new OcamlRuntimeUseAuthority(PLAN_REVISION, PROFILE, [requirement()], [occurrence("U1", 0, "HxArray.get")], repeatedPlanOutput);
		final conflictingReference = conflictingPlan.expressionIdentifier("U1", PLAN_REVISION, "HxArray.get");
		expectFailure("conflicting repeated plan", "registered with conflicting facts",
			() -> conflictingPlan.reconcileExpression(OcamlExpr.ERuntimeIdent(conflictingReference)));
		repeatedPlanOutput.observeExpression(OcamlExpr.ERuntimeIdent(firstRepeatedReference));
		repeatedPlanOutput.finishProgram();

		final copiedOutput = new OcamlFinalRuntimeUseAuthority();
		copiedOutput.beginProgram("program:runtime-use-fixture:copy", PROFILE);
		final copiedAuthority = new OcamlRuntimeUseAuthority(PLAN_REVISION, PROFILE, [requirement()], [occurrence("U1", 0)], copiedOutput);
		final original = OcamlExpr.ERuntimeIdent(copiedAuthority.expressionIdentifier("U1", PLAN_REVISION, "HxArray.set"));
		copiedAuthority.reconcileExpression(original);
		final copied = copiedOutput.copyExpressionForOutput(original, "second-binding");
		copiedOutput.observeModuleItems([
			OcamlModuleItem.ILet([{name: "original", expr: original}, {name: "copy", expr: copied}], false)
		]);
		copiedOutput.finishProgram();

		final nestedCopyOutput = new OcamlFinalRuntimeUseAuthority();
		nestedCopyOutput.beginProgram("program:runtime-use-fixture:nested-copy", PROFILE);
		final nestedCopyAuthority = new OcamlRuntimeUseAuthority(PLAN_REVISION, PROFILE, [requirement()], [occurrence("U1", 0)], nestedCopyOutput);
		final nestedReference = OcamlExpr.ERuntimeIdent(nestedCopyAuthority.expressionIdentifier("U1", PLAN_REVISION, "HxArray.set"));
		final nestedOriginal = OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [OcamlExpr.ESeq([nestedReference])]);
		nestedCopyAuthority.reconcileExpression(nestedOriginal);
		final nestedCopy = nestedCopyOutput.copyExpressionForOutput(nestedOriginal, "nested-second-binding");
		nestedCopyOutput.observeModuleItems([
			OcamlModuleItem.ILet([
				{name: "nestedOriginal", expr: nestedOriginal},
				{name: "nestedCopy", expr: nestedCopy}
			], false)
		]);
		nestedCopyOutput.finishProgram();

		final duplicateCopyOutput = new OcamlFinalRuntimeUseAuthority();
		duplicateCopyOutput.beginProgram("program:runtime-use-fixture:duplicate-copy", PROFILE);
		final duplicateCopyAuthority = new OcamlRuntimeUseAuthority(PLAN_REVISION, PROFILE, [requirement()], [occurrence("U1", 0)], duplicateCopyOutput);
		final duplicateCopyOriginal = OcamlExpr.ERuntimeIdent(duplicateCopyAuthority.expressionIdentifier("U1", PLAN_REVISION, "HxArray.set"));
		duplicateCopyAuthority.reconcileExpression(duplicateCopyOriginal);
		final firstCopy = duplicateCopyOutput.copyExpressionForOutput(duplicateCopyOriginal, "second-binding");
		final secondCopy = duplicateCopyOutput.copyExpressionForOutput(duplicateCopyOriginal, "second-binding");
		expectFailure("duplicate output-copy occurrence", "duplicate final runtime use U1:output-copy:second-binding",
			() -> duplicateCopyOutput.observeModuleItems([
				OcamlModuleItem.ILet([
					{
						name: "original",
						expr: duplicateCopyOriginal
					},
					{name: "firstCopy", expr: firstCopy},
					{name: "secondCopy", expr: secondCopy}
				], false)
			]));

		final missingOutput = new OcamlFinalRuntimeUseAuthority();
		missingOutput.beginProgram("program:runtime-use-fixture:missing", PROFILE);
		final missingAuthority = new OcamlRuntimeUseAuthority(PLAN_REVISION, PROFILE, [requirement()], [occurrence("U1", 0)], missingOutput);
		final missingReference = OcamlExpr.ERuntimeIdent(missingAuthority.expressionIdentifier("U1", PLAN_REVISION, "HxArray.set"));
		missingAuthority.reconcileExpression(missingReference);
		expectFailure("missing final use", "missing final runtime use U1", missingOutput.finishProgram);

		final orderOutput = new OcamlFinalRuntimeUseAuthority();
		orderOutput.beginProgram("program:runtime-use-fixture:order", PROFILE);
		final orderAuthority = new OcamlRuntimeUseAuthority(PLAN_REVISION, PROFILE, [requirement()], [occurrence("U1", 0), occurrence("U2", 1)], orderOutput);
		final orderU1 = OcamlExpr.ERuntimeIdent(orderAuthority.expressionIdentifier("U1", PLAN_REVISION, "HxArray.set"));
		final orderU2 = OcamlExpr.ERuntimeIdent(orderAuthority.expressionIdentifier("U2", PLAN_REVISION, "HxArray.set"));
		orderAuthority.reconcileExpression(OcamlExpr.ESeq([orderU1, orderU2]));
		orderOutput.observeModuleItems([
			OcamlModuleItem.ILet([{name: "second", expr: orderU2}, {name: "first", expr: orderU1}], false)
		]);
		expectFailure("final owner-local order", "final runtime use order", orderOutput.finishProgram);

		final unplannedOutput = new OcamlFinalRuntimeUseAuthority();
		unplannedOutput.beginProgram("program:runtime-use-fixture:unplanned", PROFILE);
		final plannedAuthority = new OcamlRuntimeUseAuthority(PLAN_REVISION, PROFILE, [requirement()], [occurrence("U1", 0)], unplannedOutput);
		final planned = OcamlExpr.ERuntimeIdent(plannedAuthority.expressionIdentifier("U1", PLAN_REVISION, "HxArray.set"));
		plannedAuthority.reconcileExpression(planned);
		final otherAuthority = new OcamlRuntimeUseAuthority(PLAN_REVISION, PROFILE, [requirement()], [occurrence("U2", 0)]);
		final unplanned = OcamlExpr.ERuntimeIdent(otherAuthority.expressionIdentifier("U2", PLAN_REVISION, "HxArray.set"));
		otherAuthority.reconcileExpression(unplanned);
		expectFailure("unplanned final use", "unplanned final runtime use U2", () -> unplannedOutput.observeExpression(unplanned));

		final wrongOwnerOutput = finalOutputForCorruption("owner");
		final wrongOwnerReference = referenceForCorruption(wrongOwnerOutput);
		Reflect.setField(wrongOwnerReference, "ownerId", "place:other-owner");
		expectFailure("wrong final owner", "wrong owner", () -> wrongOwnerOutput.observeExpression(OcamlExpr.ERuntimeIdent(cast wrongOwnerReference)));

		final wrongSymbolOutput = finalOutputForCorruption("symbol");
		final wrongSymbolReference = referenceForCorruption(wrongSymbolOutput);
		Reflect.setField(wrongSymbolReference, "exactSymbol", "HxArray.get");
		expectFailure("wrong final symbol", "wrong target symbol",
			() -> wrongSymbolOutput.observeExpression(OcamlExpr.ERuntimeIdent(cast wrongSymbolReference)));

		final wrongProfileOutput = new OcamlFinalRuntimeUseAuthority();
		wrongProfileOutput.beginProgram("program:runtime-use-fixture:profile", PROFILE);
		final wrongProfileAuthority = new OcamlRuntimeUseAuthority(PLAN_REVISION, "metal", [requirement()], [occurrence("U1", 0)], wrongProfileOutput);
		final wrongProfileReference = OcamlExpr.ERuntimeIdent(wrongProfileAuthority.expressionIdentifier("U1", PLAN_REVISION, "HxArray.set"));
		expectFailure("wrong final profile", "does not match request profile", () -> wrongProfileAuthority.reconcileExpression(wrongProfileReference));
	}

	static function finalOutputForCorruption(label:String):OcamlFinalRuntimeUseAuthority {
		final output = new OcamlFinalRuntimeUseAuthority();
		output.beginProgram('program:runtime-use-fixture:$label', PROFILE);
		return output;
	}

	static function referenceForCorruption(finalOutput:OcamlFinalRuntimeUseAuthority):Dynamic {
		// Production references are immutable and strongly typed. This test returns
		// Dynamic only so Reflect can simulate a corrupted boundary object that
		// ordinary Haxe code cannot construct.
		final checker = new OcamlRuntimeUseAuthority(PLAN_REVISION, PROFILE, [requirement()], [occurrence("U1", 0)], finalOutput);
		final reference = checker.expressionIdentifier("U1", PLAN_REVISION, "HxArray.set");
		checker.reconcileExpression(OcamlExpr.ERuntimeIdent(reference));
		return reference;
	}

	static function constructionFailures():Void {
		final checker = authority([occurrence("U1", 0)]);
		expectFailure("unknown", "unknown runtime use", () -> checker.expressionIdentifier("missing", PLAN_REVISION, "HxArray.set"));
		expectFailure("stale", "stale runtime use", () -> checker.expressionIdentifier("U1", "plan:old", "HxArray.set"));
		expectFailure("wrong symbol", "wrong target symbol", () -> checker.expressionIdentifier("U1", PLAN_REVISION, "HxArray.get"));

		final wrongDomain = authority([occurrence("U1", 0, "HxArray.set", OcamlRuntimeUseDomain.TypeIdentifier)]);
		expectFailure("wrong domain", "wrong target domain", () -> wrongDomain.expressionIdentifier("U1", PLAN_REVISION, "HxArray.set"));

		final wrongProfile = authority([occurrence("U1", 0)], "unsupported-profile");
		expectFailure("wrong profile", "not eligible for profile", () -> wrongProfile.expressionIdentifier("U1", PLAN_REVISION, "HxArray.set"));

		final sealed = authority([occurrence("U1", 0)]);
		final reference = sealed.expressionIdentifier("U1", PLAN_REVISION, "HxArray.set");
		sealed.reconcileExpression(OcamlExpr.ERuntimeIdent(reference));
		expectFailure("post seal", "after reconciliation sealed", () -> sealed.expressionIdentifier("U1", PLAN_REVISION, "HxArray.set"));
	}

	static function reconciliationFailures():Void {
		final plain = authority([occurrence("U1", 0)]);
		expectFailure("plain identifier", "plain private runtime reference HxArray.set", () -> plain.reconcileExpression(OcamlExpr.EIdent("HxArray.set")));

		final plainField = authority([occurrence("U1", 0)]);
		expectFailure("plain qualified field", "plain private runtime reference HxArray.set",
			() -> plainField.reconcileExpression(OcamlExpr.EField(OcamlExpr.EIdent("HxArray"), "set")));

		final wrongOrder = authority([occurrence("U1", 0), occurrence("U2", 1)]);
		final u1 = wrongOrder.expressionIdentifier("U1", PLAN_REVISION, "HxArray.set");
		final u2 = wrongOrder.expressionIdentifier("U2", PLAN_REVISION, "HxArray.set");
		expectFailure("owner-local order", "runtime use order",
			() -> wrongOrder.reconcileExpression(OcamlExpr.ESeq([OcamlExpr.ERuntimeIdent(u2), OcamlExpr.ERuntimeIdent(u1)])));

		final staleOwner = authority([occurrence("U1", 0)]);
		final otherAuthority = new OcamlRuntimeUseAuthority("plan:other", PROFILE, [requirement()], [occurrence("U1", 0, "HxArray.set", null, "plan:other")]);
		final staleReference = otherAuthority.expressionIdentifier("U1", "plan:other", "HxArray.set");
		expectFailure("stale final token", "stale runtime use", () -> staleOwner.reconcileExpression(OcamlExpr.ERuntimeIdent(staleReference)));
	}

	/**
		Proves that each migrated private helper rejects an ordinary unmarked call.

		An unmarked call has no link back to the compiler decision that authorized
		it. Rejecting it here prevents generated syntax from introducing a helper
		that was absent from the sealed runtime-use inventory.
	**/
	static function migratedPrivatePlainReferencesFail():Void {
		for (symbol in [
			"HxInt.add",
			"HxAnon.get",
			"HxAnon.set",
			"HxRuntime.box_bool",
			"HxRuntime.unbox_bool_or_obj",
			"HxIterator.hasNext",
			"HxIterator.next",
			"HxBytes.fill",
			"HxBytes.blit",
			"HxBytes.get",
			"HxBytes.set",
			"HxBytes.getUInt16",
			"HxBytes.setUInt16",
			"HxBytes.getInt32",
			"HxBytes.setInt32",
			"HxBytes.getInt64",
			"HxBytes.setInt64",
			"HxBytes.getFloat",
			"HxBytes.setFloat",
			"HxBytes.getDouble",
			"HxBytes.setDouble",
			"HxBytes.getData",
			"HxBytes.fastGet",
			"HxBytes.requireMultiByteInt",
			"HxBytes.length",
			"HxBytes.sub",
			"HxBytes.compare",
			"HxBytes.getString",
			"HxBytes.toString",
			"HxBytes.toHex",
			"HxBytes.create",
			"HxBytes.alloc",
			"HxBytes.ofString",
			"HxBytes.ofData",
			"HxBytes.ofHex",
			"HxRuntime.nullable_int_unwrap",
			"HxRuntime.is_null",
			"HxRuntime.hx_throw_typed"
		]) {
			final separator = symbol.indexOf(".");
			final moduleName = symbol.substr(0, separator);
			final fieldName = symbol.substr(separator + 1);
			final checker = authority([occurrence("U1", 0)]);
			expectFailure(symbol, 'plain private runtime reference $symbol',
				() -> checker.reconcileExpression(OcamlExpr.EField(OcamlExpr.EIdent(moduleName), fieldName)));
		}
	}

	static function exactRequirementRoot():Void {
		final missingRoot = Reflect.copy(requirement());
		Reflect.setField(missingRoot, "rootModules", ["HxOther"]);
		final checker = authority([occurrence("U1", 0)], PROFILE, [cast missingRoot]);
		expectFailure("wrong direct root", "direct runtime root HxArray", () -> checker.expressionIdentifier("U1", PLAN_REVISION, "HxArray.set"));
	}

	static function main():Void {
		validSameSymbolUses();
		duplicateSameSymbolUseFails();
		duplicatedReconciledSubtreeFailsFinalOutput();
		finalOutputContract();
		constructionFailures();
		reconciliationFailures();
		migratedPrivatePlainReferencesFail();
		exactRequirementRoot();
		assertTrue(true, "runtime use authority fixture completed");
		Sys.println("RUNTIME_USE_AUTHORITY:PASS");
	}
}
