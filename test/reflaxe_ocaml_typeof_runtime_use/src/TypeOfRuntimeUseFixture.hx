package;

import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlTypeOfPlan;
import reflaxe.ocaml.lowered.OcamlTypeOfPlan.OcamlTypeOfDecision;
import reflaxe.ocaml.lowered.OcamlTypeOfPlan.OcamlTypeOfInputStrategy;
import reflaxe.ocaml.lowered.OcamlTypeOfPlan.OcamlTypeOfPlanner;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Checks the complete private-runtime decision for `Type.typeof()`.

	The expected helper sequences below are written directly from the classifier
	contract. They do not call the plan's helper-selection functions, so a changed
	implementation cannot silently change both the result and its expectation.
**/
class TypeOfRuntimeUseFixture {
	static final binding:OcamlFunctionPlanBinding = {
		functionId: "TypeOfRuntimeUseFixture.main",
		programRevision: "program:type-of-runtime-use",
		bodyRevision: "body:type-of-runtime-use",
		pipelineRevision: "pipeline:type-of-runtime-use"
	};

	static final classifierSymbols = [
		"HxRuntime.is_null",
		"HxRuntime.is_boxed_bool",
		"HxType.class_",
		"HxEnum.name_opt",
		"HxType.enum_",
		"HxType.getClass",
		"HxRuntime.is_null"
	];

	public static macro function run():Expr {
		final typed = Context.typeExpr(macro {
			final dynamicValue:Dynamic = 1;
			final nullableInt:Null<Int> = null;
			final nullableInt32:Null<haxe.Int32> = null;
			final boolValue:Bool = true;
			final enumValue:TypeOfRuntimeUseEnum = TypeOfRuntimeUseEnum.Plain;
			final nullableEnum:Null<TypeOfRuntimeUseEnum> = null;
			final classValue = new TypeOfRuntimeUseClass();
			Type.typeof(dynamicValue);
			Type.typeof(nullableInt);
			Type.typeof(nullableInt32);
			Type.typeof(boolValue);
			Type.typeof(enumValue);
			Type.typeof(nullableEnum);
			Type.typeof(classValue);
			final nested = () -> Type.typeof(dynamicValue);
			nested;
		});

		final plan = new OcamlTypeOfPlanner(binding).plan(typed);
		final decisions = plan.decisions();
		assertStrategy(decisions, OcamlTypeOfInputStrategy.DirectObject, 3, classifierSymbols);
		assertStrategy(decisions, OcamlTypeOfInputStrategy.Repr, 1, classifierSymbols);
		assertStrategy(decisions, OcamlTypeOfInputStrategy.BoxBool, 1, ["HxRuntime.box_bool"].concat(classifierSymbols));
		assertStrategy(decisions, OcamlTypeOfInputStrategy.BoxEnum, 2, ["HxEnum.box_if_needed"].concat(classifierSymbols));
		if (decisions.length != 7)
			throw 'Expected seven outer-function Type.typeof decisions, received ${decisions.length}.';

		for (decision in decisions)
			proveRuntimeUses(decision);

		final enumDecision = Lambda.find(decisions, decision -> decision.inputStrategy == OcamlTypeOfInputStrategy.BoxEnum);
		if (enumDecision == null)
			throw "Expected one enum-box decision.";
		if (enumDecision.enumRuntimeName != "TypeOfRuntimeUseEnum")
			throw 'Expected the enum runtime name, received ${enumDecision.enumRuntimeName}.';
		expectFailure("missing enum name", "incompatible enum facts", () -> OcamlTypeOfPlan.requireDecision(copyWithoutEnumName(enumDecision)));
		expectFailure("wrong enum name", "stale or conflicting runtime facts",
			() -> OcamlTypeOfPlan.requireDecision(copyWithEnumName(enumDecision, enumDecision.enumRuntimeName + ":wrong")));

		expectFailure("stale binding", "belongs to another function or target pipeline", () -> plan.requirePlanBinding({
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision + ":stale"
		}));

		Sys.println("REFLAXE_OCAML_TYPE_OF_RUNTIME_USE:PASS");
		return macro null;
	}

	static function proveRuntimeUses(decision:OcamlTypeOfDecision):Void {
		OcamlTypeOfPlan.requireDecision(decision);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForTypeOf(decision);
		if (requirements.length != 1
			|| requirements[0].semanticCapability != "haxe-typeof-runtime-classification"
			|| requirements[0].rootModules.join(",") != "HxEnum,HxRuntime,HxType")
			throw 'Type.typeof decision "${decision.id}" has the wrong runtime requirement.';

		final authority = new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences);
		final references = decision.runtimeUseOccurrences.map(use -> OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(use.id, use.planRevision,
			use.exactSymbol)));
		authority.reconcileExpression(OcamlExpr.ESeq(references));

		final first = decision.runtimeUseOccurrences[0];
		expectFailure("stale helper", "stale runtime use",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(first.id, first.planRevision + ":stale", first.exactSymbol));
		expectFailure("wrong symbol", "wrong target symbol",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(first.id, first.planRevision, first.exactSymbol + "_wrong"));
		expectFailure("wrong profile", "not eligible for profile",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "unsupported-profile", requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(first.id, first.planRevision, first.exactSymbol));
		expectFailure("missing helper", "missing runtime use",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).reconcileExpression(OcamlExpr.ESeq([])));
		expectFailure("extra helper", "invalid-runtime-use",
			() -> OcamlTypeOfPlan.requireDecision(copyDecision(decision, decision.runtimeUseOccurrences.concat([first]))));

		final reordered = decision.runtimeUseOccurrences.copy();
		final next = reordered[1];
		reordered[1] = reordered[0];
		reordered[0] = next;
		expectFailure("reordered decision", "invalid-runtime-use", () -> OcamlTypeOfPlan.requireDecision(copyDecision(decision, reordered)));
		final wrongOwner = copyOccurrence(first, first.ownerId + ":wrong");
		expectFailure("wrong owner", "invalid-runtime-use",
			() -> OcamlTypeOfPlan.requireDecision(copyDecision(decision, [wrongOwner].concat(decision.runtimeUseOccurrences.slice(1)))));
	}

	static function assertStrategy(decisions:Array<OcamlTypeOfDecision>, strategy:OcamlTypeOfInputStrategy, expected:Int, symbols:Array<String>):Void {
		final selected = decisions.filter(decision -> decision.inputStrategy == strategy);
		if (selected.length != expected)
			throw 'Expected $expected ${(strategy : String)} decisions, received ${selected.length}.';
		for (decision in selected) {
			final actual = decision.runtimeUseOccurrences.map(use -> use.exactSymbol);
			if (actual.join(",") != symbols.join(","))
				throw '${(strategy : String)} expected ${symbols.join(",")}, received ${actual.join(",")}.';
		}
	}

	static function copyDecision(source:OcamlTypeOfDecision, runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>):OcamlTypeOfDecision {
		return {
			id: source.id,
			revision: source.revision,
			source: copySource(source),
			inputStrategy: source.inputStrategy,
			inputSemanticTypeId: source.inputSemanticTypeId,
			resultSemanticTypeId: source.resultSemanticTypeId,
			enumRuntimeName: source.enumRuntimeName,
			evaluationPolicy: source.evaluationPolicy,
			order: source.order,
			profileEligibility: source.profileEligibility.copy(),
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

	static function copyWithoutEnumName(source:OcamlTypeOfDecision):OcamlTypeOfDecision {
		return {
			id: source.id,
			revision: source.revision,
			source: copySource(source),
			inputStrategy: source.inputStrategy,
			inputSemanticTypeId: source.inputSemanticTypeId,
			resultSemanticTypeId: source.resultSemanticTypeId,
			evaluationPolicy: source.evaluationPolicy,
			order: source.order,
			profileEligibility: source.profileEligibility.copy(),
			runtimeRequirementIds: source.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: source.runtimeUseOccurrences.map(use -> copyOccurrence(use, use.ownerId)),
			proofId: source.proofId,
			proofClaim: source.proofClaim,
			functionId: source.functionId,
			programRevision: source.programRevision,
			bodyRevision: source.bodyRevision,
			pipelineRevision: source.pipelineRevision
		};
	}

	static function copyWithEnumName(source:OcamlTypeOfDecision, enumRuntimeName:String):OcamlTypeOfDecision {
		final copied = copyDecision(source, source.runtimeUseOccurrences.map(use -> copyOccurrence(use, use.ownerId)));
		return {
			id: copied.id,
			revision: copied.revision,
			source: {file: copied.source.file, min: copied.source.min, max: copied.source.max},
			inputStrategy: copied.inputStrategy,
			inputSemanticTypeId: copied.inputSemanticTypeId,
			resultSemanticTypeId: copied.resultSemanticTypeId,
			enumRuntimeName: enumRuntimeName,
			evaluationPolicy: copied.evaluationPolicy,
			order: copied.order,
			profileEligibility: copied.profileEligibility.copy(),
			runtimeRequirementIds: copied.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: copied.runtimeUseOccurrences,
			proofId: copied.proofId,
			proofClaim: copied.proofClaim,
			functionId: copied.functionId,
			programRevision: copied.programRevision,
			bodyRevision: copied.bodyRevision,
			pipelineRevision: copied.pipelineRevision
		};
	}

	static function copyOccurrence(source:OcamlRuntimeUseOccurrence, ownerId:String):OcamlRuntimeUseOccurrence {
		return {
			id: source.id,
			planRevision: source.planRevision,
			ownerId: ownerId,
			requirementId: source.requirementId,
			domain: source.domain,
			exactSymbol: source.exactSymbol,
			role: source.role,
			order: source.order,
			source: {
				file: source.source.file,
				min: source.source.min,
				max: source.source.max
			},
			profileEligibility: source.profileEligibility.copy(),
			cardinality: source.cardinality
		};
	}

	static function copySource(source:OcamlTypeOfDecision):OcamlLoweredSourceSpan
		return {file: source.source.file, min: source.source.min, max: source.source.max};

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
