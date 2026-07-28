#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalCarrierConversion;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalConversionRole;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalRepresentationChoice;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlUnsafeOperationKind;
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

		final immutableCaptureExpr = Context.typeExpr(macro {
			final value = 3;
			final read = function() return value;
			read();
		});
		final immutableCapture = OcamlLocalStoragePlanner.planExpression(immutableCaptureExpr);
		var capturedLocalId:Null<Int> = null;
		switch (immutableCaptureExpr.expr) {
			case TBlock(items):
				switch (items[0].expr) {
					case TVar(local, _):
						capturedLocalId = local.id;
					case _:
				}
			case _:
		}
		assertTrue(capturedLocalId != null
			&& immutableCapture.decisions().length == 0
			&& immutableCapture.isCaptured(capturedLocalId)
			&& immutableCapture.isImmutableCapture(capturedLocalId),
			"an immutable captured local should remain storage-free while exposing its capture boundary");
		final capturedIds = immutableCapture.capturedIds();
		assertTrue(capturedIds.length == 1 && capturedIds[0] == capturedLocalId, "an immutable capture should expose one deterministic local identity");
		capturedIds.push(-1);
		assertTrue(immutableCapture.capturedIds().length == 1, "mutating a returned capture inventory must not change the retained plan");
		final sameCaptureA = new OcamlLocalStoragePlan([], [7, 3, 7]);
		final sameCaptureB = new OcamlLocalStoragePlan([], [3, 7]);
		final noCapture = new OcamlLocalStoragePlan([]);
		assertTrue(sameCaptureA.revision == sameCaptureB.revision,
			"equivalent captured-local sets should have one revision regardless of input order or duplicates");
		assertTrue(sameCaptureA.revision != noCapture.revision, "captured-local evidence must participate in the storage-plan revision");
		expectFailure("captured immutable rebinding", "captured-mutation-without-cell", () -> new OcamlLocalStoragePlan([
			{
				localId: 7,
				storage: OcamlLocalStorageKind.ImmutableRebinding,
				reasons: [OcamlLocalStorageReason.CapturedAndMutated]
			}
		], [7]));
		expectFailure("captured decision without evidence", "contradictory-capture-storage", () -> new OcamlLocalStoragePlan([
			{
				localId: 7,
				storage: OcamlLocalStorageKind.RefCell,
				reasons: [OcamlLocalStorageReason.CapturedAndMutated]
			}
		]));

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

		final representedInput = Context.typeExpr(macro {var straight = 0;
			straight = 1;
			var mutable = 0;
			mutable++;
			var captured = 0;
			var readCaptured = function() return captured;
			captured = 1;
			var floating = 0.0;
			floating += 1.0;
			final arrayReceiver:Array<Int> = [7];
			var mutableArray:Array<Int> = [8];
			{
				mutableArray = [9];
			}
			var capturedArray:Array<Int> = [10];
			var replaceArray = function() capturedArray = [11];
			replaceArray();
			straight
			+ mutable
			+ readCaptured()
			+ Std.int(floating)
			+ arrayReceiver[0]
			+ mutableArray[0]
			+ capturedArray[0];
		});
		final representedStorage = OcamlLocalStoragePlanner.planExpression(representedInput);
		final representations = new OcamlRepresentationRegistry();
		representations.beginProgram("program:local-storage-fixture");
		final localRepresentations = OcamlLocalRepresentationPlanner.planExpression(representedInput, representedStorage, representations);
		final references = localRepresentations.references();
		assertTrue(localRepresentations.count == 7 && localRepresentations.admittedCount == 6,
			"mutated locals plus the immutable Array<Int> receiver should have explicit representation choices");
		assertTrue(references.length == 6, "three exact-Int and three exact-Array locals should reference the program registry");
		assertTrue(references.filter(reference -> reference.semanticTypeId == "Int"
			&& reference.domain == OcamlRepresentationDomain.InternalValue)
			.length == 1,
			"straight-line Int rebinding should use the internal-value representation domain");
		assertTrue(references.filter(reference -> reference.semanticTypeId == "Int"
			&& reference.domain == OcamlRepresentationDomain.MutableLocalStorage)
			.length == 1,
			"an incremented Int should use the mutable-local-storage representation domain");
		assertTrue(references.filter(reference -> reference.semanticTypeId == "Int"
			&& reference.domain == OcamlRepresentationDomain.CapturedLocalStorage)
			.length == 1,
			"an Int shared with a nested function should use the captured-local-storage representation domain");
		assertTrue(representations.decisions().length == 6, "the registry should retain exact Int and Array<Int> decisions for all three local domains");
		final arrayReferences = references.filter(reference -> reference.semanticTypeId == "Array<Int>");
		assertTrue(arrayReferences.length == 3
			&& arrayReferences.filter(reference -> reference.domain == OcamlRepresentationDomain.InternalValue).length == 1
			&& arrayReferences.filter(reference -> reference.domain == OcamlRepresentationDomain.MutableLocalStorage).length == 1
			&& arrayReferences.filter(reference -> reference.domain == OcamlRepresentationDomain.CapturedLocalStorage).length == 1,
			"immutable, mutable, and captured Array<Int> locals should select their exact storage domains");
		for (reference in arrayReferences) {
			assertTrue(localRepresentations.initializerConversionFor(reference.localId) == OcamlLocalCarrierConversion.Identity
				&& localRepresentations.assignmentConversionFor(reference.localId) == OcamlLocalCarrierConversion.Identity
				&& localRepresentations.readConversionFor(reference.localId) == OcamlLocalCarrierConversion.Identity,
				"every admitted Array<Int> local should seal identity initialization, replacement, and read conversions");
		}
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
		final nullIntInput = Context.typeExpr(macro {
			var internal:Null<Int> = null;
			internal = 4;
			final copied:Null<Int> = internal;
			var mutable:Null<Int> = null;
			if (copied != null) {
				mutable = 2;
			}
			var captured:Null<Int> = 1;
			final replaceCaptured = (next:Null<Int>) -> captured = next;
			replaceCaptured(copied);
			var refined:Null<Int> = 7;
			if (refined != null) {
				refined + 1;
			}
			mutable == null ? captured : mutable;
		});
		final nullIntStorage = OcamlLocalStoragePlanner.planExpression(nullIntInput);
		final nullIntBinding:OcamlFunctionPlanBinding = {
			functionId: "fixture|null-int-locals",
			programRevision: "program:local-storage-fixture",
			bodyRevision: "body:null-int-locals-v1",
			pipelineRevision: "ocaml-function-plans-v21"
		};
		final nullIntPlan = OcamlLocalRepresentationPlanner.planExpression(nullIntInput, nullIntStorage, representations, nullIntBinding);
		final nullIntReferences = nullIntPlan.references().filter(reference -> reference.semanticTypeId == "Null<Int>");
		assertTrue(nullIntReferences.length == 5, "every exact Null<Int> declaration in the focused body should reference one sealed program representation");
		assertTrue(nullIntReferences.filter(reference -> reference.domain == OcamlRepresentationDomain.InternalValue).length == 3
			&& nullIntReferences.filter(reference -> reference.domain == OcamlRepresentationDomain.MutableLocalStorage).length == 1
			&& nullIntReferences.filter(reference -> reference.domain == OcamlRepresentationDomain.CapturedLocalStorage).length == 1,
			"exact Null<Int> declarations should distinguish internal, mutable, and captured local storage");
		final nullIntConversions = nullIntPlan.conversions();
		assertTrue(nullIntConversions.filter(conversion -> conversion.role == OcamlLocalConversionRole.Initializer
			&& conversion.conversion == OcamlLocalCarrierConversion.PreserveNullableIntCarrier)
			.length > 0,
			"null and existing nullable initializers should preserve the selected Obj.t carrier");
		assertTrue(nullIntConversions.filter(conversion -> conversion.conversion == OcamlLocalCarrierConversion.BoxExactIntToNullableInt).length > 0,
			"exact Int writes should seal one Obj.repr carrier conversion");
		assertTrue(nullIntConversions.filter(conversion -> conversion.role == OcamlLocalConversionRole.Read
			&& conversion.conversion == OcamlLocalCarrierConversion.CheckedUnboxNullableInt)
			.length > 0,
			"a numeric read should seal one checked nullable-to-Int conversion");
		final nullIntUnsafe = nullIntPlan.unsafeOperations();
		assertTrue(nullIntUnsafe.filter(operation -> operation.operation == OcamlUnsafeOperationKind.ObjReprExactInt).length > 0
			&& nullIntUnsafe.filter(operation -> operation.operation == OcamlUnsafeOperationKind.CheckedNullableIntUnwrap).length > 0,
			"the focused plan should own proof records for both admitted unsafe carrier operations");
		final nullIntPlanAgain = OcamlLocalRepresentationPlanner.planExpression(nullIntInput, nullIntStorage, representations, nullIntBinding);
		assertTrue(nullIntPlanAgain.revision == nullIntPlan.revision
			&& nullIntPlanAgain.conversions()
				.map(conversion -> conversion.id)
				.join(",") == nullIntConversions.map(conversion -> conversion.id)
				.join(","),
			"planning the same typed body twice should preserve occurrence identities and the local representation revision");
		final boolInput = Context.typeExpr(macro {
			final internal:Bool = true;
			var mutable:Bool = false;
			if (internal) {
				mutable = true;
			}
			var captured:Bool = true;
			final replaceCaptured = () -> captured = false;
			replaceCaptured();
			final nullable:Null<Bool> = internal;
			nullable;
		});
		final boolStorage = OcamlLocalStoragePlanner.planExpression(boolInput);
		final boolPlan = OcamlLocalRepresentationPlanner.planExpression(boolInput, boolStorage, representations, {
			functionId: "fixture|bool-locals",
			programRevision: "program:local-storage-fixture",
			bodyRevision: "body:bool-locals-v1",
			pipelineRevision: "ocaml-function-plans-v21"
		});
		final boolReferences = boolPlan.references().filter(reference -> reference.semanticTypeId == "Bool");
		assertTrue(boolReferences.length == 3, "every declared exact Bool local should reference one sealed program representation");
		assertTrue(boolReferences.filter(reference -> reference.domain == OcamlRepresentationDomain.InternalValue).length == 1
			&& boolReferences.filter(reference -> reference.domain == OcamlRepresentationDomain.MutableLocalStorage).length == 1
			&& boolReferences.filter(reference -> reference.domain == OcamlRepresentationDomain.CapturedLocalStorage).length == 1,
			"exact Bool declarations should distinguish internal, mutable, and captured local storage");
		assertTrue(boolPlan.conversions().filter(conversion -> conversion.conversion == OcamlLocalCarrierConversion.BoxExactBoolToNullableBool).length == 1,
			"a registry-backed exact Bool local should cross once into the selected nullable carrier");
		final stringInput = Context.typeExpr(macro {
			var internal:String = "internal";
			internal = "updated";
			final copied:String = internal;
			var mutable:String = "mutable";
			if (true) {
				mutable = copied;
			}
			var captured:String = "captured";
			final replaceCaptured = () -> captured = "replaced";
			replaceCaptured();
			copied + mutable + captured;
		});
		final stringPlan = OcamlLocalRepresentationPlanner.planExpression(stringInput, OcamlLocalStoragePlanner.planExpression(stringInput), representations, {
			functionId: "fixture|string-locals",
			programRevision: "program:local-storage-fixture",
			bodyRevision: "body:string-locals-v1",
			pipelineRevision: "ocaml-function-plans-v21"
		});
		final stringReferences = stringPlan.references().filter(reference -> reference.semanticTypeId == "String");
		assertTrue(stringReferences.length == 4,
			"every admitted exact String declaration and carrier-preserving copy should reference one sealed program representation");
		assertTrue(stringReferences.filter(reference -> reference.domain == OcamlRepresentationDomain.InternalValue).length == 2
			&& stringReferences.filter(reference -> reference.domain == OcamlRepresentationDomain.MutableLocalStorage).length == 1
			&& stringReferences.filter(reference -> reference.domain == OcamlRepresentationDomain.CapturedLocalStorage).length == 1,
			"exact String declarations should distinguish internal, mutable, and captured local storage");
		for (reference in stringReferences) {
			assertTrue(stringPlan.initializerConversionFor(reference.localId) == OcamlLocalCarrierConversion.Identity
				&& stringPlan.assignmentConversionFor(reference.localId) == OcamlLocalCarrierConversion.Identity
				&& stringPlan.readConversionFor(reference.localId) == OcamlLocalCarrierConversion.Identity,
				"every admitted String local should seal identity initialization, replacement, and read conversions");
		}
		final nullStringInput = Context.typeExpr(macro {
			final explicitNull:String = null;
			explicitNull;
		});
		final nullStringPlan = OcamlLocalRepresentationPlanner.planExpression(nullStringInput, OcamlLocalStoragePlanner.planExpression(nullStringInput),
			representations);
		assertTrue(nullStringPlan.references().filter(reference -> reference.semanticTypeId == "String").length == 0,
			"an explicit null local String should remain unadmitted until it has an occurrence-bound sentinel conversion");
		final dynamicStringInput = Context.typeExpr(macro {
			final dynamicValue:Dynamic = "dynamic";
			final converted:String = cast dynamicValue;
			final copied:String = converted;
			copied;
		});
		final dynamicStringPlan = OcamlLocalRepresentationPlanner.planExpression(dynamicStringInput,
			OcamlLocalStoragePlanner.planExpression(dynamicStringInput), representations);
		assertTrue(dynamicStringPlan.references().filter(reference -> reference.semanticTypeId == "String").length == 0,
			"a Dynamic-to-String cast and its dependent copy should not borrow the exact String carrier without a typed conversion");
		final unsupportedBoolExpression = Context.typeExpr(macro {
			final nullable:Null<Bool> = true == false;
			nullable;
		});
		final unsupportedBoolPlan = OcamlLocalRepresentationPlanner.planExpression(unsupportedBoolExpression,
			OcamlLocalStoragePlanner.planExpression(unsupportedBoolExpression), representations, {
				functionId: "fixture|unsupported-bool-expression",
				programRevision: "program:local-storage-fixture",
				bodyRevision: "body:unsupported-bool-expression-v1",
				pipelineRevision: "ocaml-function-plans-v21"
			});
		assertTrue(unsupportedBoolPlan.references().filter(reference -> reference.semanticTypeId == "Null<Bool>").length == 0,
			"an arbitrary exact Bool expression should not publish a partial nullable-Bool representation");
		assertTrue(unsupportedBoolPlan.conversions().length == 0,
			"an arbitrary exact Bool expression should not publish a nullable-Bool conversion without its own carrier owner");
		final unsupportedBoolLocalInput = Context.typeExpr(macro {
			final source:Bool = true == false;
			final alias:Bool = source;
			final nullable:Null<Bool> = alias;
			nullable;
		});
		final unsupportedBoolLocalPlan = OcamlLocalRepresentationPlanner.planExpression(unsupportedBoolLocalInput,
			OcamlLocalStoragePlanner.planExpression(unsupportedBoolLocalInput), representations, {
				functionId: "fixture|unsupported-bool-local",
				programRevision: "program:local-storage-fixture",
				bodyRevision: "body:unsupported-bool-local-v1",
				pipelineRevision: "ocaml-function-plans-v21"
			});
		assertTrue(unsupportedBoolLocalPlan.references()
			.filter(reference -> reference.semanticTypeId == "Bool" || reference.semanticTypeId == "Null<Bool>")
			.length == 0,
			"a Bool local with an unowned operator initializer and its nullable dependent should both remain unplanned");
		assertTrue(unsupportedBoolLocalPlan.conversions().length == 0,
			"an unplanned Bool source local must not lend a guessed carrier to a nullable dependent");
		final nullBoolInput = Context.typeExpr(macro {
			var internal:Null<Bool> = null;
			internal = false;
			final copied:Null<Bool> = internal;
			var mutable:Null<Bool> = null;
			if (copied) {
				mutable = true;
			}
			var captured:Null<Bool> = true;
			final readCaptured = () -> captured && copied;
			final replaceCaptured = () -> captured = false;
			replaceCaptured();
			if (!captured) {
				mutable = false;
			}
			readCaptured() || mutable;});
		final nullBoolStorage = OcamlLocalStoragePlanner.planExpression(nullBoolInput);
		final nullBoolBinding:OcamlFunctionPlanBinding = {
			functionId: "fixture|null-bool-locals",
			programRevision: "program:local-storage-fixture",
			bodyRevision: "body:null-bool-locals-v1",
			pipelineRevision: "ocaml-function-plans-v21"
		};
		final nullBoolPlan = OcamlLocalRepresentationPlanner.planExpression(nullBoolInput, nullBoolStorage, representations, nullBoolBinding);
		final nullBoolReferences = nullBoolPlan.references().filter(reference -> reference.semanticTypeId == "Null<Bool>");
		assertTrue(nullBoolReferences.length == 4, "every exact Null<Bool> declaration in the focused body should reference one sealed program representation");
		assertTrue(nullBoolReferences.filter(reference -> reference.domain == OcamlRepresentationDomain.InternalValue).length == 2
			&& nullBoolReferences.filter(reference -> reference.domain == OcamlRepresentationDomain.MutableLocalStorage).length == 1
			&& nullBoolReferences.filter(reference -> reference.domain == OcamlRepresentationDomain.CapturedLocalStorage).length == 1,
			"exact Null<Bool> declarations should distinguish internal, mutable, and captured local storage");
		final nullBoolConversions = nullBoolPlan.conversions();
		assertTrue(nullBoolConversions.filter(conversion -> conversion.conversion == OcamlLocalCarrierConversion.PreserveNullableBoolCarrier).length > 0,
			"null and existing nullable-Bool values should preserve the selected Obj.t carrier");
		assertTrue(nullBoolConversions.filter(conversion -> conversion.conversion == OcamlLocalCarrierConversion.BoxExactBoolToNullableBool).length > 0,
			"exact Bool writes should seal one Obj.repr carrier conversion");
		assertTrue(nullBoolConversions.filter(conversion -> conversion.role == OcamlLocalConversionRole.Read
			&& conversion.conversion == OcamlLocalCarrierConversion.NullableBoolTruthiness)
			.length >= 4,
			"if, logical-and, logical-or, and logical-not reads should seal nullable-Bool truthiness");
		final nullBoolUnsafe = nullBoolPlan.unsafeOperations();
		assertTrue(nullBoolUnsafe.filter(operation -> operation.operation == OcamlUnsafeOperationKind.ObjReprExactBool).length > 0
			&& nullBoolUnsafe.filter(operation -> operation.operation == OcamlUnsafeOperationKind.NullableBoolTruthiness).length > 0,
			"the focused plan should own proof records for nullable-Bool boxing and truthiness");
		final nullBoolPlanAgain = OcamlLocalRepresentationPlanner.planExpression(nullBoolInput, nullBoolStorage, representations, nullBoolBinding);
		assertTrue(nullBoolPlanAgain.revision == nullBoolPlan.revision
			&& nullBoolPlanAgain.conversions()
				.map(conversion -> conversion.id)
				.join(",") == nullBoolConversions.map(conversion -> conversion.id)
				.join(","),
			"planning the same nullable-Bool body twice should preserve occurrence identities and the local representation revision");
		final nullableBoolConversion = nullBoolConversions[0];
		final wrongFamilyDecision:OcamlLocalRepresentationDecision = {
			localId: nullableBoolConversion.localId,
			choice: cast nullIntPlan.choiceFor(nullIntConversions[0].localId),
			initializerConversion: OcamlLocalCarrierConversion.LegacyCoercion,
			assignmentConversion: OcamlLocalCarrierConversion.LegacyCoercion,
			readConversion: OcamlLocalCarrierConversion.LegacyCoercion
		};
		expectFailure("wrong nullable primitive family", "wrong-conversion-family",
			() -> new OcamlLocalRepresentationPlan([wrongFamilyDecision], [nullableBoolConversion]));
		final concreteBoolBoundaryInput = Context.typeExpr(macro {
			final nullable:Null<Bool> = null;
			final concrete:Bool = nullable;
			concrete;
		});
		final concreteBoolBoundaryPlan = OcamlLocalRepresentationPlanner.planExpression(concreteBoolBoundaryInput,
			OcamlLocalStoragePlanner.planExpression(concreteBoolBoundaryInput), representations, {
				functionId: "fixture|null-bool-concrete-boundary",
				programRevision: "program:local-storage-fixture",
				bodyRevision: "body:null-bool-concrete-boundary-v1",
				pipelineRevision: "ocaml-function-plans-v21"
			});
		final concreteBoolBoundaryLocalId = switch (concreteBoolBoundaryInput.expr) {
			case TBlock(expressions):
				switch (expressions[0].expr) {
					case TVar(local, _): local.id;
					case _: throw "concrete Bool boundary declaration changed shape";
				}
			case _: throw "concrete Bool boundary block changed shape";
		}
		assertTrue(concreteBoolBoundaryPlan.choiceFor(concreteBoolBoundaryLocalId) == null,
			"a Null<Bool> local consumed by a concrete Bool boundary should remain outside the truthiness-only slice");
		assertTrue(concreteBoolBoundaryPlan.conversions().length == 0,
			"an unadmitted concrete Bool boundary must not publish partial nullable-Bool occurrence conversions");
		final excludedNullableCopyInput = Context.typeExpr(macro {
			final source:Null<Bool> = null;
			final concrete:Bool = source;
			final copy:Null<Bool> = source;
			concrete || copy;});
		final excludedNullableCopyPlan = OcamlLocalRepresentationPlanner.planExpression(excludedNullableCopyInput,
			OcamlLocalStoragePlanner.planExpression(excludedNullableCopyInput), representations, {
				functionId: "fixture|excluded-nullable-copy",
				programRevision: "program:local-storage-fixture",
				bodyRevision: "body:excluded-nullable-copy-v1",
				pipelineRevision: "ocaml-function-plans-v21"
			});
		assertTrue(excludedNullableCopyPlan.references().filter(reference -> reference.semanticTypeId == "Null<Bool>").length == 0,
			"a nullable copy must not claim carrier preservation when its source local was excluded by a concrete-Bool boundary");
		assertTrue(excludedNullableCopyPlan.conversions().length == 0,
			"excluding a nullable source must also remove dependent carrier-preserving occurrence records");
		final dynamicCarrierInput = Context.typeExpr(macro {
			final text:Dynamic = cast("text" : String);
			final decimal:Dynamic = cast(1.5 : Float);
			final flag:Dynamic = cast(true : Bool);
			final empty:Dynamic = null;
			Std.string(text) + Std.string(decimal) + Std.string(flag) + Std.string(empty);
		});
		final dynamicCarrierBinding:OcamlFunctionPlanBinding = {
			functionId: "fixture|dynamic-carrier",
			programRevision: "program:local-storage-fixture",
			bodyRevision: "body:dynamic-carrier-v1",
			pipelineRevision: "ocaml-function-plans-v52"
		};
		final dynamicCarrierPlan = OcamlLocalRepresentationPlanner.planExpression(dynamicCarrierInput,
			OcamlLocalStoragePlanner.planExpression(dynamicCarrierInput), representations, dynamicCarrierBinding);
		final dynamicReferences = dynamicCarrierPlan.references().filter(reference -> reference.semanticTypeId == "Dynamic");
		final dynamicConversions = dynamicCarrierPlan.conversions();
		assertTrue(dynamicReferences.length == 4
			&& dynamicReferences.filter(reference -> reference.domain == OcamlRepresentationDomain.InternalValue
				&& reference.representationId == "representation:Dynamic:internal-value")
				.length == 4,
			'each immutable Dynamic local should reference the one internal Obj.t representation; observed ${dynamicReferences.length} references and ${dynamicConversions.map(conversion -> conversion.conversion + ":" + conversion.inputSemanticTypeId).join(",")} conversions');
		assertTrue(dynamicConversions.filter(conversion -> conversion.conversion == OcamlLocalCarrierConversion.BoxConcreteToDynamic
			&& conversion.inputSemanticTypeId == "String")
			.length == 1,
			"a concrete String should enter Dynamic through one proof-backed Obj.repr conversion");
		assertTrue(dynamicConversions.filter(conversion -> conversion.conversion == OcamlLocalCarrierConversion.BoxConcreteToDynamic
			&& conversion.inputSemanticTypeId == "Float")
			.length == 1,
			"an exact Float should enter Dynamic through one proof-backed Obj.repr conversion");
		assertTrue(dynamicConversions.filter(conversion -> conversion.conversion == OcamlLocalCarrierConversion.BoxExactBoolToDynamic
			&& conversion.inputSemanticTypeId == "Bool")
			.length == 1,
			"exact Bool should enter Dynamic through its distinguishable runtime box");
		assertTrue(dynamicConversions.filter(conversion -> conversion.conversion == OcamlLocalCarrierConversion.PreserveDynamicCarrier
			&& conversion.inputSemanticTypeId == "Dynamic")
			.length == 1,
			"the null sentinel should preserve the already-selected Dynamic carrier");
		final dynamicUnsafe = dynamicCarrierPlan.unsafeOperations();
		assertTrue(dynamicUnsafe.filter(operation -> operation.operation == OcamlUnsafeOperationKind.ObjReprConcreteToDynamic).length == 2
			&& dynamicUnsafe.filter(operation -> operation.operation == OcamlUnsafeOperationKind.BoxExactBoolToDynamic).length == 1,
			"only concrete and Bool Dynamic crossings should publish unsafe-operation proof records");
		final uninitializedDynamicInput = Context.typeExpr(macro {
			var value:Dynamic;
			value;
		});
		final uninitializedDynamicPlan = OcamlLocalRepresentationPlanner.planExpression(uninitializedDynamicInput,
			OcamlLocalStoragePlanner.planExpression(uninitializedDynamicInput), representations, {
				functionId: "fixture|uninitialized-dynamic",
				programRevision: "program:local-storage-fixture",
				bodyRevision: "body:uninitialized-dynamic-v1",
				pipelineRevision: "ocaml-function-plans-v52"
			});
		assertTrue(uninitializedDynamicPlan.references().filter(reference -> reference.semanticTypeId == "Dynamic").length == 0
			&& uninitializedDynamicPlan.conversions().length == 0,
			"an implicitly initialized Dynamic local must remain outside the immutable occurrence-bound slice");
		final reassignedDynamicInput = Context.typeExpr(macro {
			var value:Dynamic = cast("first" : String);
			value = cast(7 : Int);
			Std.string(value);
		});
		final reassignedDynamicPlan = OcamlLocalRepresentationPlanner.planExpression(reassignedDynamicInput,
			OcamlLocalStoragePlanner.planExpression(reassignedDynamicInput), representations, {
				functionId: "fixture|reassigned-dynamic",
				programRevision: "program:local-storage-fixture",
				bodyRevision: "body:reassigned-dynamic-v1",
				pipelineRevision: "ocaml-function-plans-v52"
			});
		assertTrue(reassignedDynamicPlan.references().filter(reference -> reference.semanticTypeId == "Dynamic").length == 0
			&& reassignedDynamicPlan.conversions().length == 0,
			"a reassigned Dynamic local must reject the entire immutable slice instead of publishing its initializer conversion");
		final wrongDynamicRole:Dynamic = Reflect.copy(dynamicConversions[0]);
		Reflect.setField(wrongDynamicRole, "role", OcamlLocalConversionRole.Assignment);
		final dynamicDecisions:Array<OcamlLocalRepresentationDecision> = dynamicReferences.map(reference -> ({
			localId: reference.localId,
			choice: OcamlLocalRepresentationChoice.ProgramDecision(reference.representationId, reference.semanticTypeId, reference.domain),
			initializerConversion: OcamlLocalCarrierConversion.LegacyCoercion,
			assignmentConversion: OcamlLocalCarrierConversion.LegacyCoercion,
			readConversion: OcamlLocalCarrierConversion.LegacyCoercion
		}));
		final wrongDynamicConversions = dynamicConversions.copy();
		wrongDynamicConversions[0] = cast wrongDynamicRole;
		expectFailure("wrong Dynamic conversion role", "invalid-dynamic-conversion-role",
			() -> new OcamlLocalRepresentationPlan(dynamicDecisions, wrongDynamicConversions));
		final returnedConversion = nullIntConversions[0];
		Reflect.setField(returnedConversion, "proofId", "changed-by-caller");
		assertTrue(nullIntPlan.conversions()[0].proofId != "changed-by-caller", "mutating a returned conversion must not change the sealed occurrence plan");
		final duplicateConversion = nullIntPlan.conversions()[0];
		final duplicateReference = nullIntPlan.referenceFor(duplicateConversion.localId);
		assertTrue(duplicateReference != null, "the duplicate-conversion fixture should retain its local representation");
		final duplicateDecision:OcamlLocalRepresentationDecision = {
			localId: duplicateConversion.localId,
			choice: OcamlLocalRepresentationChoice.ProgramDecision(duplicateReference.representationId, duplicateReference.semanticTypeId,
				duplicateReference.domain),
			initializerConversion: OcamlLocalCarrierConversion.LegacyCoercion,
			assignmentConversion: OcamlLocalCarrierConversion.LegacyCoercion,
			readConversion: OcamlLocalCarrierConversion.LegacyCoercion
		};
		expectFailure("duplicate local conversion", "duplicate-local-conversion",
			() -> new OcamlLocalRepresentationPlan([duplicateDecision], [duplicateConversion, duplicateConversion]));
		final wrongCarrier:Dynamic = Reflect.copy(duplicateConversion);
		Reflect.setField(wrongCarrier, "inputCarrierTypeId", "wrong-carrier");
		expectFailure("wrong local conversion carrier", "wrong-conversion-carrier",
			() -> new OcamlLocalRepresentationPlan([duplicateDecision], [cast wrongCarrier]));
		final unsafeConversion = nullIntConversions.filter(conversion -> conversion.unsafeOperation != null)[0];
		final mismatchedUnsafe:Dynamic = Reflect.copy(unsafeConversion);
		final unsafeProof:Dynamic = Reflect.copy(unsafeConversion.unsafeOperation);
		Reflect.setField(unsafeProof, "proofId", "wrong-proof");
		Reflect.setField(mismatchedUnsafe, "unsafeOperation", unsafeProof);
		expectFailure("mismatched unsafe proof", "unsafe-proof-mismatch", () -> new OcamlLocalRepresentationPlan([
			{
				localId: unsafeConversion.localId,
				choice: cast nullIntPlan.choiceFor(unsafeConversion.localId),
				initializerConversion: OcamlLocalCarrierConversion.LegacyCoercion,
				assignmentConversion: OcamlLocalCarrierConversion.LegacyCoercion,
				readConversion: OcamlLocalCarrierConversion.LegacyCoercion
			}
		], [cast mismatchedUnsafe]));
		final changedBinding:OcamlFunctionPlanBinding = {
			functionId: nullIntBinding.functionId,
			programRevision: nullIntBinding.programRevision,
			bodyRevision: "body:stale",
			pipelineRevision: nullIntBinding.pipelineRevision
		};
		assertTrue(nullIntPlan.conversionFor(changedBinding, duplicateConversion.localId, duplicateConversion.role, duplicateConversion.source) == null,
			"a stale body binding must not resolve an occurrence conversion");
		final nullableArrayInput = Context.typeExpr(macro {
			final nullable:Array<Int> = null;
			nullable;
		});
		final nullableArrayRepresentations = OcamlLocalRepresentationPlanner.planExpression(nullableArrayInput,
			OcamlLocalStoragePlanner.planExpression(nullableArrayInput), representations);
		assertTrue(nullableArrayRepresentations.count == 0, "a null-initialized Array<Int> local should stay on the existing sentinel conversion path");
		final dynamicInitializerInput = Context.typeExpr(macro {
			final dynamicValue:Dynamic = [1];
			final converted:Array<Int> = cast dynamicValue;
			converted;
		});
		final dynamicInitializerPlan = OcamlLocalRepresentationPlanner.planExpression(dynamicInitializerInput,
			OcamlLocalStoragePlanner.planExpression(dynamicInitializerInput), representations);
		assertTrue(dynamicInitializerPlan.count == 0, "an Array<Int> local initialized through a Dynamic cast should stay on the explicit conversion path");
		final nullableReplacementInput = Context.typeExpr(macro {
			var nullableReplacement:Array<Int> = [1];
			{
				nullableReplacement = null;
			}
			nullableReplacement;
		});
		final nullableReplacementPlan = OcamlLocalRepresentationPlanner.planExpression(nullableReplacementInput,
			OcamlLocalStoragePlanner.planExpression(nullableReplacementInput), representations);
		final nullableReplacementLocal = switch (nullableReplacementInput.expr) {
			case TBlock(expressions):
				switch (expressions[0].expr) {
					case TVar(local, _): local;
					case _: throw "nullable replacement declaration changed shape";
				}
			case _: throw "nullable replacement regression input changed shape";
		}
		switch (nullableReplacementPlan.choiceFor(nullableReplacementLocal.id)) {
			case Unmigrated(_):
			case _:
				throw "a local that can receive null should remain outside direct Array<Int> carrier conversion";
		}
		final dynamicReplacementInput = Context.typeExpr(macro {
			final dynamicValue:Dynamic = [1];
			var converted:Array<Int> = [2];
			{
				converted = cast dynamicValue;
			}
			converted;
		});
		final dynamicReplacementPlan = OcamlLocalRepresentationPlanner.planExpression(dynamicReplacementInput,
			OcamlLocalStoragePlanner.planExpression(dynamicReplacementInput), representations);
		final dynamicReplacementLocal = switch (dynamicReplacementInput.expr) {
			case TBlock(expressions):
				switch (expressions[1].expr) {
					case TVar(local, _): local;
					case _: throw "Dynamic replacement declaration changed shape";
				}
			case _: throw "Dynamic replacement regression input changed shape";
		}
		switch (dynamicReplacementPlan.choiceFor(dynamicReplacementLocal.id)) {
			case Unmigrated(_):
			case _:
				throw "a local assigned through a Dynamic cast should remain outside direct Array<Int> carrier conversion";
		}
		final returnedReference = references[0];
		Reflect.setField(returnedReference, "representationId", "changed-by-caller");
		assertTrue(localRepresentations.referenceFor(returnedReference.localId).representationId != "changed-by-caller",
			"mutating a returned local reference must not change the sealed function plan");
		final legacyAssignmentPlan = new OcamlLocalRepresentationPlan([
			{
				localId: 70,
				choice: OcamlLocalRepresentationChoice.ProgramDecision("representation:Array<Int>:internal-value", "Array<Int>",
					OcamlRepresentationDomain.InternalValue),
				initializerConversion: OcamlLocalCarrierConversion.Identity,
				assignmentConversion: OcamlLocalCarrierConversion.LegacyCoercion,
				readConversion: OcamlLocalCarrierConversion.Identity
			}
		]);
		final identityAssignmentPlan = new OcamlLocalRepresentationPlan([
			{
				localId: 70,
				choice: OcamlLocalRepresentationChoice.ProgramDecision("representation:Array<Int>:internal-value", "Array<Int>",
					OcamlRepresentationDomain.InternalValue),
				initializerConversion: OcamlLocalCarrierConversion.Identity,
				assignmentConversion: OcamlLocalCarrierConversion.Identity,
				readConversion: OcamlLocalCarrierConversion.Identity
			}
		]);
		assertTrue(legacyAssignmentPlan.revision != identityAssignmentPlan.revision,
			"changing one sealed local-carrier conversion should change the function-local representation revision");

		expectFailure("duplicate local", "planned more than once", () -> new OcamlLocalStoragePlan([straightLine, straightLine]));
		expectFailure("unmigrated identity conversion", "unmigrated but selects a non-legacy carrier conversion", () -> new OcamlLocalRepresentationPlan([
			{
				localId: 8,
				choice: OcamlLocalRepresentationChoice.Unmigrated("Array<Int>"),
				initializerConversion: OcamlLocalCarrierConversion.Identity,
				assignmentConversion: OcamlLocalCarrierConversion.LegacyCoercion,
				readConversion: OcamlLocalCarrierConversion.LegacyCoercion
			}
		]));
		expectFailure("duplicate local representation choice", "more than one representation choice", () -> new OcamlLocalRepresentationPlan([
			{
				localId: 7,
				choice: OcamlLocalRepresentationChoice.Unmigrated("Float"),
				initializerConversion: OcamlLocalCarrierConversion.LegacyCoercion,
				assignmentConversion: OcamlLocalCarrierConversion.LegacyCoercion,
				readConversion: OcamlLocalCarrierConversion.LegacyCoercion
			},
			{
				localId: 7,
				choice: OcamlLocalRepresentationChoice.Unmigrated("Float"),
				initializerConversion: OcamlLocalCarrierConversion.LegacyCoercion,
				assignmentConversion: OcamlLocalCarrierConversion.LegacyCoercion,
				readConversion: OcamlLocalCarrierConversion.LegacyCoercion
			}
		]));
		Sys.println("REFLAXE_OCAML_LOCAL_STORAGE_PLANNER_FIXTURE:PASS");
	}
}
#end
