import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
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

	static function occurrence(id:String, order:Int, ?symbol:String = "HxArray.set", ?domain:OcamlRuntimeUseDomain,
			?planRevision:String = PLAN_REVISION):OcamlRuntimeUseOccurrence {
		return {
			id: id,
			planRevision: planRevision,
			ownerId: "place:array-simple-assignment",
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
		constructionFailures();
		reconciliationFailures();
		migratedPrivatePlainReferencesFail();
		exactRequirementRoot();
		assertTrue(true, "runtime use authority fixture completed");
		Sys.println("RUNTIME_USE_AUTHORITY:PASS");
	}
}
