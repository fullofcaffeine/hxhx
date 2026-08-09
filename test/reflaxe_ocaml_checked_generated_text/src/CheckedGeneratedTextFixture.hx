import reflaxe.ocaml.runtimegen.OcamlCheckedGeneratedText;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementCause;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSourceKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSubjectKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Proves that compiler-generated text can use private runtime names only through
	ordered placeholders authorized by the generated module's sealed plan.
**/
class CheckedGeneratedTextFixture {
	static inline final OWNER_ID = "compiler-generated:Fixture.ml";
	static inline final PLAN_REVISION = "plan:generated-text:v1";
	static inline final REQUIREMENT_ID = "compiler:generated:Fixture:array";

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

	static function requirement():OcamlRuntimeRequirement {
		return {
			id: REQUIREMENT_ID,
			sourceKind: OcamlRuntimeRequirementSourceKind.CompilerInfrastructure,
			sourceId: OWNER_ID,
			source: {file: "compiler-generated/Fixture.ml", min: 0, max: 0},
			semanticCapability: "fixture-array-runtime",
			cause: OcamlRuntimeRequirementCause.CompilerInfrastructure,
			decisionId: "fixture:emit-array-runtime",
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.GeneratedModule,
				id: "Fixture"
			},
			implementationFeature: "fixture-array-runtime-v1",
			rootModules: ["HxArray"],
			profileEligibility: ["portable"],
			explanation: "The fixture-generated module uses the checked Haxe array runtime."
		};
	}

	static function occurrence(id:String, order:Int):OcamlRuntimeUseOccurrence {
		return {
			id: id,
			planRevision: PLAN_REVISION,
			ownerId: OWNER_ID,
			requirementId: REQUIREMENT_ID,
			domain: OcamlRuntimeUseDomain.GeneratedText,
			exactSymbol: "HxArray.set",
			role: "fixture-store",
			order: order,
			source: {
				file: "compiler-generated/Fixture.ml",
				min: 0,
				max: 0
			},
			profileEligibility: ["portable"],
			cardinality: 1
		};
	}

	static function builder(occurrences:Array<OcamlRuntimeUseOccurrence>):OcamlCheckedGeneratedText {
		return new OcamlCheckedGeneratedText(OWNER_ID, PLAN_REVISION, "portable", [requirement()], occurrences);
	}

	static function validAndDeterministic():Void {
		final checked = builder([occurrence("U1", 0), occurrence("U2", 1)]);
		checked.addLiteral("let first = ");
		checked.addRuntimeUse("U1", PLAN_REVISION, "HxArray.set");
		checked.addLiteral("\nlet second = ");
		checked.addRuntimeUse("U2", PLAN_REVISION, "HxArray.set");
		checked.addLiteral("\n");
		final record = checked.seal();
		OcamlCheckedGeneratedText.verify(record);
		assertTrue(record.content == "let first = HxArray.set\nlet second = HxArray.set\n", "checked content changed");
		assertTrue(record.ownerId == OWNER_ID && record.planRevision == PLAN_REVISION, "checked identity changed");
		assertTrue(record.orderedUseIds.join(",") == "U1,U2", "checked use order changed");
		assertTrue(record.contentHash.startsWith("sha256:") && record.contentHash.length == 71, "checked content hash is invalid");

		final repeat = builder([occurrence("U1", 0), occurrence("U2", 1)]);
		repeat.addLiteral("let first = ");
		repeat.addRuntimeUse("U1", PLAN_REVISION, "HxArray.set");
		repeat.addLiteral("\nlet second = ");
		repeat.addRuntimeUse("U2", PLAN_REVISION, "HxArray.set");
		repeat.addLiteral("\n");
		assertTrue(repeat.seal().contentHash == record.contentHash, "clean-repeat content hash changed");
	}

	static function corruptionFails():Void {
		final missing = builder([occurrence("U1", 0), occurrence("U2", 1)]);
		missing.addRuntimeUse("U1", PLAN_REVISION, "HxArray.set");
		expectFailure("missing", "missing runtime use U2", () -> missing.seal());

		final duplicate = builder([occurrence("U1", 0)]);
		duplicate.addRuntimeUse("U1", PLAN_REVISION, "HxArray.set");
		expectFailure("duplicate", "constructed more than once", () -> duplicate.addRuntimeUse("U1", PLAN_REVISION, "HxArray.set"));

		final reordered = builder([occurrence("U1", 0), occurrence("U2", 1)]);
		reordered.addRuntimeUse("U2", PLAN_REVISION, "HxArray.set");
		reordered.addRuntimeUse("U1", PLAN_REVISION, "HxArray.set");
		expectFailure("reordered", "runtime use order", () -> reordered.seal());

		final stale = builder([occurrence("U1", 0)]);
		expectFailure("stale", "stale runtime use", () -> stale.addRuntimeUse("U1", "plan:old", "HxArray.set"));

		final wrongSymbol = builder([occurrence("U1", 0)]);
		expectFailure("wrong symbol", "wrong target symbol", () -> wrongSymbol.addRuntimeUse("U1", PLAN_REVISION, "HxArray.get"));

		final literal = builder([]);
		literal.addLiteral("let forged = HxArray.set\n");
		expectFailure("literal private reference", "private runtime name HxArray", () -> literal.seal());

		final dataOnly = builder([]);
		dataOnly.addLiteral("let name = \"HxArray.set\"\n(* HxType.class_ is documentation, not a call. *)\n");
		final dataRecord = dataOnly.seal();
		assertTrue(dataRecord.content.contains("HxArray.set"), "private-looking string data should remain unchanged");

		final stringPosition = builder([occurrence("U1", 0)]);
		stringPosition.addLiteral("let value = \"");
		stringPosition.addRuntimeUse("U1", PLAN_REVISION, "HxArray.set");
		stringPosition.addLiteral("\"\n");
		expectFailure("placeholder in string", "is not an OCaml code identifier", () -> stringPosition.seal());

		final forgedMarker = builder([occurrence("U1", 0)]);
		forgedMarker.addLiteral("let forged = ReflaxeCheckedRuntimeUse0\nlet hidden = \"");
		forgedMarker.addRuntimeUse("U1", PLAN_REVISION, "HxArray.set");
		forgedMarker.addLiteral("\"\n");
		expectFailure("forged placeholder marker", "reserved runtime placeholder", () -> forgedMarker.seal());

		final wrongProfile = new OcamlCheckedGeneratedText(OWNER_ID, PLAN_REVISION, "metal", [requirement()], [occurrence("U1", 0)]);
		expectFailure("wrong profile", "not eligible for profile metal", () -> wrongProfile.addRuntimeUse("U1", PLAN_REVISION, "HxArray.set"));

		final foreignOccurrence = occurrence("U1", 0);
		Reflect.setField(foreignOccurrence, "ownerId", "compiler-generated:Other.ml");
		expectFailure("foreign owner", "belongs to compiler-generated:Other.ml", () -> builder([foreignOccurrence]));
	}

	static function changedHashFails():Void {
		final checked = builder([occurrence("U1", 0)]);
		checked.addRuntimeUse("U1", PLAN_REVISION, "HxArray.set");
		final record = checked.seal();
		Reflect.setField(record, "content", record.content + " ");
		expectFailure("changed hash", "content hash", () -> OcamlCheckedGeneratedText.verify(record));
	}

	static function main():Void {
		validAndDeterministic();
		corruptionFails();
		changedHashFails();
		Sys.println("CHECKED_GENERATED_TEXT:PASS");
	}
}
