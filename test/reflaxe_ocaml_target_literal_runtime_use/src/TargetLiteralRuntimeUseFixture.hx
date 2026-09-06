#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type.TConstant;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;
import reflaxe.ocaml.target.HaxeOcamlTargetLiteralAdapter;
import reflaxe.ocaml.target.OcamlTargetLiteralFact;
import reflaxe.ocaml.target.OcamlTargetLiteralLowerer;
import reflaxe.ocaml.target.OcamlTargetLiteralLowerer.OcamlTargetLiteralCarrier;
import reflaxe.ocaml.target.OcamlTargetLiteralRuntimeUse.OcamlTargetLiteralRuntimeUseContract;
import reflaxe.ocaml.target.OcamlTargetLiteralRuntimeUse.OcamlTargetLiteralRuntimeUseDecision;

/**
	Proves exact private-runtime ownership for a Boolean literal entering `Dynamic`.

	The source plan, request authority, shared target lowerer, final-output ledger,
	and public runtime-requirement row must all agree before OCaml can be printed.
**/
class TargetLiteralRuntimeUseFixture {
	static inline final PROFILE = "portable";
	static inline final SOURCE_ID = "Main|Main|static|main:target-literal:0";

	public static macro function run():Expr {
		final source:OcamlLoweredSourceSpan = {file: "src/Main.hx", min: 17, max: 21};
		final fact = dynamicBool(true);
		final decision = requireDecision(fact, source);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForTargetLiteral(decision);
		proveDecision(decision, requirements);
		proveCheckedLowering(fact, decision, requirements, source);
		provePlanFailures(fact, decision, source);
		proveAuthorityFailures(fact, decision, requirements, source);
		proveLowererFailures(fact, decision, requirements, source);
		proveRequirementFailures(requirements[0]);
		Sys.println("REFLAXE_OCAML_TARGET_LITERAL_RUNTIME_USE:PASS");
		return macro null;
	}

	static function dynamicBool(value:Bool):OcamlTargetLiteralFact {
		final fact = HaxeOcamlTargetLiteralAdapter.fromConstant(TBool(value), Context.typeof(macro(null : Dynamic)));
		if (fact == null)
			throw "stock Haxe adapter rejected a Dynamic Boolean literal";
		return fact;
	}

	static function requireDecision(fact:OcamlTargetLiteralFact, source:OcamlLoweredSourceSpan):OcamlTargetLiteralRuntimeUseDecision {
		final decision = OcamlTargetLiteralRuntimeUseContract.forLiteral(fact, OcamlTargetLiteralCarrier.DynamicOrTypeParameter, SOURCE_ID, source);
		if (decision == null)
			throw "Dynamic Boolean literal did not select a runtime-use decision";
		OcamlTargetLiteralRuntimeUseContract.requireForLiteral(fact, OcamlTargetLiteralCarrier.DynamicOrTypeParameter, SOURCE_ID, source, decision);
		return decision;
	}

	static function proveDecision(decision:OcamlTargetLiteralRuntimeUseDecision, requirements:Array<OcamlRuntimeRequirement>):Void {
		final occurrence = decision.runtimeUseOccurrences[0];
		if (decision.runtimeRequirementIds.length != 1
			|| occurrence.ownerId != decision.id
			|| occurrence.planRevision != decision.revision
			|| occurrence.exactSymbol != OcamlTargetLiteralRuntimeUseContract.EXACT_SYMBOL
			|| occurrence.domain != OcamlRuntimeUseDomain.ExpressionIdentifier
			|| occurrence.role != OcamlTargetLiteralRuntimeUseContract.ROLE
			|| occurrence.cardinality != 1
			|| requirements.length != 1
			|| requirements[0].id != decision.runtimeRequirementIds[0]
			|| requirements[0].sourceId != SOURCE_ID
			|| requirements[0].subject.id != "Bool -> Dynamic"
			|| requirements[0].rootModules.join(",") != "HxRuntime"
			|| requirements[0].semanticCapability != OcamlRuntimeRequirementLedger.HAXE_DYNAMIC_BOOL_LITERAL) {
			throw "Dynamic Boolean literal lost its exact runtime requirement or occurrence";
		}
		OcamlRuntimeRequirementLedger.requireTargetLiteralRequirement(requirements[0]);
		final direct = OcamlTargetLiteralRuntimeUseContract.forLiteral(OcamlTargetLiteralFact.boolLiteral(true, "Bool"), OcamlTargetLiteralCarrier.Direct,
			"direct", {
				file: "src/Main.hx",
				min: 1,
				max: 2
			});
		if (direct != null)
			throw "a direct Boolean literal acquired private-runtime authority";
	}

	static function proveCheckedLowering(fact:OcamlTargetLiteralFact, decision:OcamlTargetLiteralRuntimeUseDecision,
			requirements:Array<OcamlRuntimeRequirement>, source:OcamlLoweredSourceSpan):Void {
		final finalOutput = new OcamlFinalRuntimeUseAuthority();
		finalOutput.beginProgram("program:target-literal-runtime-use", PROFILE);
		final authority = new OcamlRuntimeUseAuthority(decision.revision, PROFILE, requirements, decision.runtimeUseOccurrences, finalOutput);
		final authorization = OcamlTargetLiteralRuntimeUseContract.authorize(decision, fact, OcamlTargetLiteralCarrier.DynamicOrTypeParameter, SOURCE_ID,
			source, authority);
		final expression = OcamlTargetLiteralLowerer.buildNonNull(fact, OcamlTargetLiteralCarrier.DynamicOrTypeParameter, authorization);
		authority.reconcileExpression(expression);
		if (new OcamlASTPrinter().printExpr(expression) != "HxRuntime.box_bool true")
			throw "checked Dynamic Boolean literal changed its generated OCaml";
		finalOutput.observeExpression(expression, "Main::main::dynamic-bool-literal");
		finalOutput.finishProgram();
	}

	static function provePlanFailures(fact:OcamlTargetLiteralFact, decision:OcamlTargetLiteralRuntimeUseDecision, source:OcamlLoweredSourceSpan):Void {
		final occurrence = decision.runtimeUseOccurrences[0];
		expectFailure("missing occurrence", "invalid-runtime-use",
			() -> OcamlTargetLiteralRuntimeUseContract.requireForLiteral(fact, DynamicOrTypeParameter, SOURCE_ID, source, withUses(decision, [])));
		expectFailure("duplicate occurrence", "invalid-runtime-use",
			() -> OcamlTargetLiteralRuntimeUseContract.requireForLiteral(fact, DynamicOrTypeParameter, SOURCE_ID, source,
				withUses(decision, [occurrence, occurrence])));
		expectFailure("wrong owner", "invalid-runtime-use",
			() -> OcamlTargetLiteralRuntimeUseContract.requireForLiteral(fact, DynamicOrTypeParameter, SOURCE_ID, source,
				withUses(decision, [copyUse(occurrence, "target-literal:foreign")])));
		expectFailure("wrong symbol", "invalid-runtime-use",
			() -> OcamlTargetLiteralRuntimeUseContract.requireForLiteral(fact, DynamicOrTypeParameter, SOURCE_ID, source,
				withUses(decision, [copyUse(occurrence, null, "HxRuntime.hx_null")])));
		expectFailure("wrong profile", "invalid-runtime-use",
			() -> OcamlTargetLiteralRuntimeUseContract.requireForLiteral(fact, DynamicOrTypeParameter, SOURCE_ID, source,
				withUses(decision, [copyUse(occurrence, null, null, ["portable"])])));
		expectFailure("stale source owner", "invalid-runtime-use",
			() -> OcamlTargetLiteralRuntimeUseContract.requireForLiteral(fact, DynamicOrTypeParameter, SOURCE_ID + ":stale", source, decision));
		expectFailure("foreign literal", "invalid-runtime-use",
			() -> OcamlTargetLiteralRuntimeUseContract.requireForLiteral(dynamicBool(false), DynamicOrTypeParameter, SOURCE_ID, source, decision));
	}

	static function proveAuthorityFailures(fact:OcamlTargetLiteralFact, decision:OcamlTargetLiteralRuntimeUseDecision,
			requirements:Array<OcamlRuntimeRequirement>, source:OcamlLoweredSourceSpan):Void {
		final occurrence = decision.runtimeUseOccurrences[0];
		expectFailure("missing requirement", "has no exact requirement",
			() -> OcamlTargetLiteralRuntimeUseContract.authorize(decision, fact, DynamicOrTypeParameter, SOURCE_ID, source,
				new OcamlRuntimeUseAuthority(decision.revision, PROFILE, [], decision.runtimeUseOccurrences)));
		expectFailure("wrong profile", "not eligible",
			() -> OcamlTargetLiteralRuntimeUseContract.authorize(decision, fact, DynamicOrTypeParameter, SOURCE_ID, source,
				new OcamlRuntimeUseAuthority(decision.revision, "unsupported", requirements, decision.runtimeUseOccurrences)));
		final duplicate = new OcamlRuntimeUseAuthority(decision.revision, PROFILE, requirements, decision.runtimeUseOccurrences);
		duplicate.expressionIdentifier(occurrence.id, decision.revision, occurrence.exactSymbol);
		expectFailure("duplicate construction", "constructed more than once",
			() -> OcamlTargetLiteralRuntimeUseContract.authorize(decision, fact, DynamicOrTypeParameter, SOURCE_ID, source, duplicate));
	}

	static function proveLowererFailures(fact:OcamlTargetLiteralFact, decision:OcamlTargetLiteralRuntimeUseDecision,
			requirements:Array<OcamlRuntimeRequirement>, source:OcamlLoweredSourceSpan):Void {
		expectFailure("missing lowerer authority", "requires checked", () -> OcamlTargetLiteralLowerer.buildNonNull(fact, DynamicOrTypeParameter));
		final authority = new OcamlRuntimeUseAuthority(decision.revision, PROFILE, requirements, decision.runtimeUseOccurrences);
		final authorization = OcamlTargetLiteralRuntimeUseContract.authorize(decision, fact, DynamicOrTypeParameter, SOURCE_ID, source, authority);
		expectFailure("irrelevant lowerer authority", "unexpected private-runtime authority",
			() -> OcamlTargetLiteralLowerer.buildNonNull(fact, Direct, authorization));
	}

	static function proveRequirementFailures(requirement:OcamlRuntimeRequirement):Void {
		expectFailure("wrong requirement root", "sealed target-literal contract",
			() -> OcamlRuntimeRequirementLedger.requireTargetLiteralRequirement(copyRequirement(requirement, {
				rootModules: ["HxType"]
			})));
		expectFailure("missing requirement source owner", "sealed target-literal contract",
			() -> OcamlRuntimeRequirementLedger.requireTargetLiteralRequirement(copyRequirement(requirement, {
				sourceId: ""
			})));
		expectFailure("invalid requirement decision", "sealed target-literal contract",
			() -> OcamlRuntimeRequirementLedger.requireTargetLiteralRequirement(copyRequirement(requirement, {
				decisionId: "target-literal:broken"
			})));
		expectFailure("wrong requirement subject", "sealed target-literal contract",
			() -> OcamlRuntimeRequirementLedger.requireTargetLiteralRequirement(copyRequirement(requirement, {
				subjectId: "Bool"
			})));
	}

	static function copyRequirement(requirement:OcamlRuntimeRequirement, overrides:TargetLiteralRequirementOverrides):OcamlRuntimeRequirement {
		final decisionId = overrides.decisionId == null ? requirement.decisionId : overrides.decisionId;
		return {
			id: overrides.decisionId == null ? requirement.id : decisionId + ":runtime:" + OcamlRuntimeRequirementLedger.HAXE_DYNAMIC_BOOL_LITERAL,
			sourceKind: requirement.sourceKind,
			sourceId: overrides.sourceId == null ? requirement.sourceId : overrides.sourceId,
			source: requirement.source,
			semanticCapability: requirement.semanticCapability,
			cause: requirement.cause,
			decisionId: decisionId,
			subject: {
				kind: requirement.subject.kind,
				id: overrides.subjectId == null ? requirement.subject.id : overrides.subjectId
			},
			implementationFeature: requirement.implementationFeature,
			rootModules: overrides.rootModules == null ? requirement.rootModules.copy() : overrides.rootModules,
			profileEligibility: requirement.profileEligibility,
			explanation: requirement.explanation
		};
	}

	static function withUses(decision:OcamlTargetLiteralRuntimeUseDecision, uses:Array<OcamlRuntimeUseOccurrence>):OcamlTargetLiteralRuntimeUseDecision {
		return {
			id: decision.id,
			revision: decision.revision,
			sourceId: decision.sourceId,
			source: decision.source,
			literalIdentity: decision.literalIdentity,
			semanticTypeId: decision.semanticTypeId,
			boolValue: decision.boolValue,
			carrier: decision.carrier,
			profileEligibility: decision.profileEligibility.copy(),
			runtimeRequirementIds: decision.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: uses
		};
	}

	static function copyUse(source:OcamlRuntimeUseOccurrence, ?ownerId:String, ?exactSymbol:String, ?profiles:Array<String>):OcamlRuntimeUseOccurrence {
		return {
			id: source.id,
			planRevision: source.planRevision,
			ownerId: ownerId == null ? source.ownerId : ownerId,
			requirementId: source.requirementId,
			domain: source.domain,
			exactSymbol: exactSymbol == null ? source.exactSymbol : exactSymbol,
			role: source.role,
			order: source.order,
			source: source.source,
			profileEligibility: profiles == null ? source.profileEligibility.copy() : profiles,
			cardinality: source.cardinality
		};
	}

	static function expectFailure(label:String, marker:String, operation:Void->Void):Void {
		var failed = false;
		try {
			operation();
		} catch (error:String) {
			failed = true;
			if (error.indexOf(marker) < 0)
				throw '$label failed with an unexpected message: $error';
		}
		if (!failed)
			throw '$label should have failed';
	}
}

private typedef TargetLiteralRequirementOverrides = {
	final ?sourceId:String;
	final ?decisionId:String;
	final ?subjectId:String;
	final ?rootModules:Array<String>;
}
#end
