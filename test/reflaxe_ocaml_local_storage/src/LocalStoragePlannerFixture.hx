#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan.OcamlLocalStorageDecision;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan.OcamlLocalStorageKind;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan.OcamlLocalStorageReason;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlanner;

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

		assertDecision(macro {
			var value = 0;
			var read = function() return value;
			value = 1;
			read();
		}, OcamlLocalStorageKind.RefCell,
			["captured-and-mutated", "straight-line-assignment"], "captured mutation");

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
		final firstPass = OcamlLocalStoragePlanner.planExpression(deterministicInput).decisions();
		final secondPass = OcamlLocalStoragePlanner.planExpression(deterministicInput).decisions();
		assertTrue(firstPass.length == 2
			&& firstPass[0].localId < firstPass[1].localId, "multiple storage decisions should use deterministic local-id order");
		assertTrue(firstPass.map(decision -> decision.localId).join(",") == secondPass.map(decision -> decision.localId).join(","),
			"planning the same typed body twice should preserve decision identities and order");

		expectFailure("duplicate local", "planned more than once", () -> new OcamlLocalStoragePlan([straightLine, straightLine]));
		Sys.println("REFLAXE_OCAML_LOCAL_STORAGE_PLANNER_FIXTURE:PASS");
	}
}
#end
