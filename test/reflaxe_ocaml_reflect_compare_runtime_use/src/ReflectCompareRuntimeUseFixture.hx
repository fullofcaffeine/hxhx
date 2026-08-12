import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlReflectComparePlan;
import reflaxe.ocaml.lowered.OcamlReflectComparePlan.OcamlReflectCompareDecision;
import reflaxe.ocaml.lowered.OcamlReflectComparePlan.OcamlReflectCompareDomain;
import reflaxe.ocaml.lowered.OcamlReflectComparePlan.OcamlReflectComparePlanner;
import reflaxe.ocaml.runtimegen.OcamlReflectCompareRuntimeRequirementRecorder;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Defines the private runtime calls that typed `Reflect.compare` domains need.

	The expected symbols and order are written in this fixture. The test types real
	Haxe function values, but it does not read the target builder or generated
	OCaml to decide what the plan should contain.
**/
class ReflectCompareRuntimeUseFixture {
	static final binding:OcamlFunctionPlanBinding = {
		functionId: "ReflectCompareRuntimeUseFixture.main",
		programRevision: "program:reflect-compare-runtime-use",
		bodyRevision: "body:reflect-compare-runtime-use",
		pipelineRevision: "pipeline:reflect-compare-runtime-use"
	};

	public static macro function run():Expr {
		final typed = Context.typeExpr(macro {
			final compareInts:(Int, Int) -> Int = Reflect.compare;
			final compareFloats:(Float, Float) -> Int = Reflect.compare;
			final compareStrings:(String, String) -> Int = Reflect.compare;
			final compareNullableStrings:(Null<String>, Null<String>) -> Int = Reflect.compare;
			compareInts;
			compareFloats;
			compareStrings;
			compareNullableStrings;
		});

		final decisions = new OcamlReflectComparePlanner(binding).plan(typed).decisions();
		final intDecision = requireDomain(decisions, OcamlReflectCompareDomain.Int);
		final floatDecision = requireDomain(decisions, OcamlReflectCompareDomain.Float);
		final stringDecision = requireDomain(decisions, OcamlReflectCompareDomain.String);
		final nullableStringDecision = requireDomain(decisions, OcamlReflectCompareDomain.NullableString);

		assertSymbols(intDecision, []);
		assertSymbols(floatDecision, ["HxRuntime.hx_throw"]);
		assertSymbols(stringDecision, ["HxString.isNull", "HxString.isNull", "HxRuntime.hx_throw"]);
		assertSymbols(nullableStringDecision, ["HxString.isNull", "HxString.isNull"]);
		assertRoles(stringDecision, ["left-null-check", "right-null-check", "throw-invalid-comparison"]);
		assertRoles(nullableStringDecision, ["left-null-check", "right-null-check"]);

		proveAuthority(floatDecision);
		proveAuthority(stringDecision);
		proveAuthority(nullableStringDecision);
		proveCorruption(stringDecision);

		Sys.println("REFLAXE_OCAML_REFLECT_COMPARE_RUNTIME_USE:PASS");
		return macro null;
	}

	static function proveAuthority(decision:OcamlReflectCompareDecision):Void {
		final requirements = OcamlReflectCompareRuntimeRequirementRecorder.requirementsFor(decision);
		final authority = new OcamlRuntimeUseAuthority(OcamlRuntimeUseModel.planRevision(binding), "portable", requirements, decision.runtimeUseOccurrences);
		final references = decision.runtimeUseOccurrences.map(use -> OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(use.id, use.planRevision,
			use.exactSymbol)));
		authority.reconcileExpression(OcamlExpr.ESeq(references));
	}

	static function proveCorruption(decision:OcamlReflectCompareDecision):Void {
		final uses = decision.runtimeUseOccurrences;
		final first = uses[0];
		expectFailure("missing occurrence", "invalid-runtime-use", () -> OcamlReflectComparePlan.requireDecision(copyDecision(decision, uses.slice(1))));
		expectFailure("duplicate occurrence", "invalid-runtime-use",
			() -> OcamlReflectComparePlan.requireDecision(copyDecision(decision, uses.concat([first]))));
		expectFailure("reordered occurrence", "invalid-runtime-use",
			() -> OcamlReflectComparePlan.requireDecision(copyDecision(decision, [uses[1], uses[0], uses[2]])));
		expectFailure("wrong owner", "invalid-runtime-use",
			() -> OcamlReflectComparePlan.requireDecision(copyDecision(decision, [copyOccurrence(first, first.ownerId + ":wrong")].concat(uses.slice(1)))));
		expectFailure("wrong symbol", "invalid-runtime-use",
			() -> OcamlReflectComparePlan.requireDecision(copyDecision(decision,
				[copyOccurrence(first, null, first.exactSymbol + "_wrong")].concat(uses.slice(1)))));
		expectFailure("stale revision", "invalid-runtime-use",
			() -> OcamlReflectComparePlan.requireDecision(copyDecision(decision,
				[copyOccurrence(first, null, null, first.planRevision + ":stale")].concat(uses.slice(1)))));
		expectFailure("wrong profile", "invalid-runtime-use",
			() -> OcamlReflectComparePlan.requireDecision(copyDecision(decision,
				[copyOccurrence(first, null, null, null, ["portable"])].concat(uses.slice(1)))));
		expectFailure("wrong domain", "invalid-runtime-use", () -> OcamlReflectComparePlan.requireDecision(copyDecision(decision, [
			copyOccurrence(first, null, null, null, null, OcamlRuntimeUseDomain.TypeIdentifier)
		].concat(uses.slice(1)))));

		final requirements = OcamlReflectCompareRuntimeRequirementRecorder.requirementsFor(decision);
		expectFailure("plain private reference", "plain private runtime reference",
			() -> new OcamlRuntimeUseAuthority(OcamlRuntimeUseModel.planRevision(binding), "portable", requirements,
				uses).reconcileExpression(OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "isNull")));
	}

	static function requireDomain(decisions:Array<OcamlReflectCompareDecision>, domain:OcamlReflectCompareDomain):OcamlReflectCompareDecision {
		final selected = decisions.filter(decision -> decision.domain == domain);
		if (selected.length != 1)
			throw 'Expected one ${(domain : String)} decision, received ${selected.length}.';
		return selected[0];
	}

	static function assertSymbols(decision:OcamlReflectCompareDecision, expected:Array<String>):Void {
		final actual = decision.runtimeUseOccurrences.map(use -> use.exactSymbol);
		if (actual.join(",") != expected.join(","))
			throw '${(decision.domain : String)} expected runtime symbols ${expected.join(",")}, received ${actual.join(",")}.';
	}

	static function assertRoles(decision:OcamlReflectCompareDecision, expected:Array<String>):Void {
		final actual = decision.runtimeUseOccurrences.map(use -> use.role);
		if (actual.join(",") != expected.join(","))
			throw '${(decision.domain : String)} expected runtime roles ${expected.join(",")}, received ${actual.join(",")}.';
	}

	static function copyDecision(source:OcamlReflectCompareDecision, runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>):OcamlReflectCompareDecision {
		return {
			id: source.id,
			source: {file: source.source.file, min: source.source.min, max: source.source.max},
			domain: source.domain,
			runtimeRequirementIds: source.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: runtimeUseOccurrences,
			proofId: source.proofId,
			proofClaim: source.proofClaim,
			functionId: source.functionId,
			programRevision: source.programRevision,
			bodyRevision: source.bodyRevision,
			pipelineRevision: source.pipelineRevision
		};
	}

	static function copyOccurrence(source:OcamlRuntimeUseOccurrence, ?ownerId:String, ?exactSymbol:String, ?planRevision:String,
			?profileEligibility:Array<String>, ?domain:OcamlRuntimeUseDomain):OcamlRuntimeUseOccurrence {
		return {
			id: source.id,
			planRevision: planRevision ?? source.planRevision,
			ownerId: ownerId ?? source.ownerId,
			requirementId: source.requirementId,
			domain: domain ?? source.domain,
			exactSymbol: exactSymbol ?? source.exactSymbol,
			role: source.role,
			order: source.order,
			source: {
				file: source.source.file,
				min: source.source.min,
				max: source.source.max
			},
			profileEligibility: profileEligibility == null ? source.profileEligibility.copy() : profileEligibility.copy(),
			cardinality: source.cardinality
		};
	}

	static function expectFailure(label:String, marker:String, operation:Void->Void):Void {
		var message:Null<String> = null;
		try {
			operation();
		} catch (error:Dynamic) {
			message = Std.string(error);
		}
		if (message == null || !message.contains(marker))
			throw '$label must fail with "$marker", received ${message == null ? "no failure" : message}.';
	}
}
