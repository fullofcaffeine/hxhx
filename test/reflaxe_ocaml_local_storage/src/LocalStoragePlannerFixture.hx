#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalRepresentationChoice;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan.OcamlLocalStorageDecision;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan.OcamlLocalStorageKind;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan.OcamlLocalStorageReason;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlanner;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlanner;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/** Focused executable checks for local-storage decisions and explanations. */
class LocalStoragePlannerFixture {
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
			if (message.indexOf(expectedMessage) < 0)
				throw '$label failed with an unexpected message: $message';
		}
		if (!failed)
			throw '$label should have failed.';
	}

	static function plan(source:Expr):OcamlLocalStoragePlan {
		return OcamlLocalStoragePlanner.planExpression(Context.typeExpr(source));
	}

	static function onlyDecision(storagePlan:OcamlLocalStoragePlan, label:String):OcamlLocalStorageDecision {
		final decisions = storagePlan.decisions();
		assertTrue(decisions.length == 1, '$label should produce exactly one mutated-local decision, got ${decisions.length}.');
		return decisions[0];
	}

	static function reasonIds(decision:OcamlLocalStorageDecision):Array<String> {
		return decision.reasons.map(reason -> {
			final reasonId:String = reason;
			return reasonId;
		});
	}

	static function assertDecision(source:Expr, storage:OcamlLocalStorageKind, expectedReasons:Array<String>, label:String):OcamlLocalStorageDecision {
		final storagePlan = plan(source);
		final decision = onlyDecision(storagePlan, label);
		assertTrue(decision.storage == storage, '$label selected ${decision.storage}, expected $storage.');
		assertTrue(reasonIds(decision).join(",") == expectedReasons.join(","),
			'$label reasons were ${reasonIds(decision).join(",")}, expected ${expectedReasons.join(",")}.');
		assertTrue(storagePlan.requiresRef(decision.localId) == (storage == OcamlLocalStorageKind.RefCell),
			'$label ref lookup disagrees with its typed decision.');
		return decision;
	}

	/** Runs during compilation so the fixture can inspect Haxe `TypedExpr` values. */
	public static function run():Void {
		final straightLine = assertDecision(macro {
			var value = 0;
			value = 1;
			value;
		}, OcamlLocalStorageKind.ImmutableRebinding,
			["straight-line-assignment"], "straight-line assignment");

		assertDecision(macro {
			var value = 0;
			value += 1;
			value;
		}, OcamlLocalStorageKind.RefCell, ["compound-assignment"], "compound assignment");

		assertDecision(macro {
			var value = 0;
			value++;
			value;
		}, OcamlLocalStorageKind.RefCell, ["increment-or-decrement"], "increment");

		assertDecision(macro {
			var value = 0;
			var assigned = (value = 1);
			assigned;
		}, OcamlLocalStorageKind.RefCell,
			["expression-position-mutation"], "expression-position assignment");

		assertDecision(macro {
			var value = 0;
			while (value < 1) {
				value = 1;
			}
			value;
		}, OcamlLocalStorageKind.RefCell,
			["loop-mutation", "nested-block-mutation"], "loop assignment");

		final nestedBlock = plan(macro {
			var outer = 0;
			{
				var inner = 0;
				inner = 1;
				outer = 2;
				inner;
			}
			outer;
		});
		final nestedBlockDecisions = nestedBlock.decisions();
		assertTrue(nestedBlockDecisions.length == 2, "a nested block should plan its own local and the mutated outer local once each");
		final sameScopeNested = nestedBlockDecisions.filter(decision -> decision.storage == OcamlLocalStorageKind.ImmutableRebinding);
		final crossingNested = nestedBlockDecisions.filter(decision -> decision.storage == OcamlLocalStorageKind.RefCell);
		assertTrue(sameScopeNested.length == 1 && reasonIds(sameScopeNested[0]).join(",") == "straight-line-assignment",
			"a straight-line local declared inside a nested block should remain an immutable rebinding");
		assertTrue(crossingNested.length == 1 && reasonIds(crossingNested[0]).join(",") == "nested-block-mutation",
			"a nested-block write to an outer local should use the shared cell");

		assertDecision(macro {
			var value = 0;
			var read = function() return value;
			value = 1;
			read();
		}, OcamlLocalStorageKind.RefCell,
			["captured-and-mutated", "straight-line-assignment"], "captured mutation");

		final nestedFunction = plan(macro {
			var outer = 0;
			var mutate = function() {
				var inner = 0;
				inner = 1;
				outer = 2;
				return inner;
			};
			mutate();
			outer;
		});
		final nestedDecisions = nestedFunction.decisions();
		assertTrue(nestedDecisions.length == 2, "a nested function should plan its own local and its captured outer local once each");
		final immutableNested = nestedDecisions.filter(decision -> decision.storage == OcamlLocalStorageKind.ImmutableRebinding);
		final capturedNested = nestedDecisions.filter(decision -> decision.storage == OcamlLocalStorageKind.RefCell);
		assertTrue(immutableNested.length == 1 && reasonIds(immutableNested[0]).join(",") == "straight-line-assignment",
			"a straight-line local declared inside a nested function should remain an immutable rebinding");
		assertTrue(capturedNested.length == 1 && reasonIds(capturedNested[0]).join(",") == "captured-and-mutated,nested-function-mutation",
			"a nested function write to an outer local should use the captured shared cell");

		final copy = plan(macro {
			var value = 0;
			value = 1;
			value;
		});
		final returnedDecision = onlyDecision(copy, "defensive copy");
		returnedDecision.reasons.push(OcamlLocalStorageReason.CapturedAndMutated);
		final retainedDecision = copy.decisionFor(returnedDecision.localId);
		assertTrue(retainedDecision != null && reasonIds(retainedDecision).join(",") == "straight-line-assignment",
			"mutating a returned reason list must not change the retained plan");

		final deterministicInput = Context.typeExpr(macro {
			var first = 0;
			var second = 0;
			second++;
			first += 1;
			first + second;
		});
		final firstPlan = OcamlLocalStoragePlanner.planExpression(deterministicInput);
		final secondPlan = OcamlLocalStoragePlanner.planExpression(deterministicInput);
		final firstPass = firstPlan.decisions();
		final secondPass = secondPlan.decisions();
		assertTrue(firstPass.length == 2
			&& firstPass[0].localId < firstPass[1].localId, "multiple storage decisions should use deterministic local-id order");
		assertTrue(firstPass.map(decision -> decision.localId).join(",") == secondPass.map(decision -> decision.localId).join(","),
			"planning the same typed body twice should preserve decision identities and order");
		assertTrue(firstPlan.revision == secondPlan.revision && StringTools.startsWith(firstPlan.revision, "sha256:"),
			"the same typed body should produce one stable content revision");
		final canonicalA = new OcamlLocalStoragePlan([
			{
				localId: 7,
				storage: OcamlLocalStorageKind.RefCell,
				reasons: [
					OcamlLocalStorageReason.NestedBlockMutation,
					OcamlLocalStorageReason.LoopMutation
				]
			}
		]);
		final canonicalB = new OcamlLocalStoragePlan([
			{
				localId: 7,
				storage: OcamlLocalStorageKind.RefCell,
				reasons: [
					OcamlLocalStorageReason.LoopMutation,
					OcamlLocalStorageReason.NestedBlockMutation
				]
			}
		]);
		assertTrue(canonicalA.revision == canonicalB.revision, "equivalent storage reasons should have one revision regardless of input order");

		final representedInput = Context.typeExpr(macro {
			var straight = 0;
			straight = 1;
			var mutable = 0;
			mutable++;
			var captured = 0;
			var readCaptured = function() return captured;
			captured = 1;
			var floating = 0.0;
			floating += 1.0;
			straight + mutable + readCaptured() + Std.int(floating);
		});
		final representedStorage = OcamlLocalStoragePlanner.planExpression(representedInput);
		final representations = new OcamlRepresentationRegistry();
		representations.beginProgram("program:local-storage-fixture");
		final localRepresentations = OcamlLocalRepresentationPlanner.planExpression(representedInput, representedStorage, representations);
		final references = localRepresentations.references();
		assertTrue(localRepresentations.count == 4 && localRepresentations.admittedCount == 3,
			"every mutated local should have an explicit representation choice, while only exact Int is admitted in this slice");
		assertTrue(references.length == 3, "all three mutated exact-Int locals should reference the program representation registry");
		assertTrue(references.filter(reference -> reference.domain == OcamlRepresentationDomain.InternalValue).length == 1,
			"straight-line Int rebinding should use the internal-value representation domain");
		assertTrue(references.filter(reference -> reference.domain == OcamlRepresentationDomain.MutableLocalStorage).length == 1,
			"an incremented Int should use the mutable-local-storage representation domain");
		assertTrue(references.filter(reference -> reference.domain == OcamlRepresentationDomain.CapturedLocalStorage).length == 1,
			"an Int shared with a nested function should use the captured-local-storage representation domain");
		assertTrue(representations.decisions()
			.length == 3, "the program registry should retain one exact-Int decision for each selected local-storage domain");
		var unmigratedFloatCount = 0;
		for (storageDecision in representedStorage.decisions()) {
			switch (localRepresentations.choiceFor(storageDecision.localId)) {
				case Unmigrated("Float"):
					unmigratedFloatCount += 1;
				case _:
			}
		}
		assertTrue(unmigratedFloatCount == 1,
			"the mutated Float local should be explicitly marked as unmigrated instead of being silently reclassified during syntax construction");
		final returnedReference = references[0];
		Reflect.setField(returnedReference, "representationId", "changed-by-caller");
		assertTrue(localRepresentations.referenceFor(returnedReference.localId).representationId != "changed-by-caller",
			"mutating a returned local reference must not change the sealed function plan");

		expectFailure("duplicate local", "planned more than once", () -> new OcamlLocalStoragePlan([straightLine, straightLine]));
		expectFailure("duplicate local representation choice", "more than one representation choice", () -> new OcamlLocalRepresentationPlan([
			{localId: 7, choice: OcamlLocalRepresentationChoice.Unmigrated("Float")},
			{localId: 7, choice: OcamlLocalRepresentationChoice.Unmigrated("Float")}
		]));
		Sys.println("REFLAXE_OCAML_LOCAL_STORAGE_PLANNER_FIXTURE:PASS");
	}
}
#end
