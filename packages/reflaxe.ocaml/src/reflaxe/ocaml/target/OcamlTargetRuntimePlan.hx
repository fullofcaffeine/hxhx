package reflaxe.ocaml.target;

import haxe.crypto.Sha256;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeReference;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** Mutable collection storage is private to construction; consumers receive defensive copies. **/
private typedef RuntimePlanCollection = {
	final ownerIdentity:String;
	final revision:String;
	final requirements:Array<OcamlRuntimeRequirement>;
	final occurrences:Array<OcamlRuntimeUseOccurrence>;
	final usesByPath:Map<String, OcamlRuntimeUseOccurrence>;
}

/**
	Plans exact runtime uses from immutable shared-target expressions.

	Each source identity combines the owning fact and structural expression path.
	The shared facts do not carry physical source locations. The empty diagnostic
	span uses the existing unavailable-location convention; it is not a filename
	or a claim about source offsets. Runtime authorization uses the exact fact,
	plan revision, symbol, profile, and occurrence identity instead.
**/
class OcamlTargetRuntimePlan {
	public final revision:String;

	final requirements:Array<OcamlRuntimeRequirement> = [];
	final occurrences:Array<OcamlRuntimeUseOccurrence> = [];
	final usesByPath:Map<String, OcamlRuntimeUseOccurrence> = [];
	final authority:OcamlRuntimeUseAuthority;

	public function new(ownerIdentity:String, bodyIdentity:String, expressions:Array<OcamlTargetExpressionFact>, profile:String,
			?finalOutput:OcamlFinalRuntimeUseAuthority) {
		if (ownerIdentity == null || ownerIdentity.length == 0 || bodyIdentity == null || bodyIdentity.length == 0)
			throw "Shared target runtime planning requires exact owner and body identities";
		if (profile != "portable" && profile != "metal")
			throw "Shared target runtime planning requires a supported profile";
		revision = "sha256:" + Sha256.encode(OcamlTargetDeclarationCodec.encode(["target-runtime-plan-v1", ownerIdentity, bodyIdentity, profile]));
		final collection:RuntimePlanCollection = {
			ownerIdentity: ownerIdentity,
			revision: revision,
			requirements: requirements,
			occurrences: occurrences,
			usesByPath: usesByPath
		};
		for (expression in expressions)
			collect(collection, expression);
		authority = new OcamlRuntimeUseAuthority(revision, profile, requirements, occurrences, finalOutput);
	}

	static function collect(collection:RuntimePlanCollection, expression:OcamlTargetExpressionFact):Void {
		final ownerIdentity = collection.ownerIdentity;
		final revision = collection.revision;
		final requirements = collection.requirements;
		final occurrences = collection.occurrences;
		final usesByPath = collection.usesByPath;
		final symbol:Null<String> = switch (expression.kind) {
			case NullableIntNullExpression: "HxRuntime.hx_null";
			case UnwrapNullableIntExpression: "HxRuntime.nullable_int_unwrap";
			case TestNullableIntNullExpression: "HxRuntime.is_null";
			case _: null;
		};
		if (symbol != null) {
			final exactSymbol:String = symbol;
			if (usesByPath.exists(expression.path))
				throw "Shared target runtime plan repeats a structural expression path";
			final sourceId = ownerIdentity + ":" + expression.path;
			final id = "target-nullable-int:"
				+ Sha256.encode(OcamlTargetDeclarationCodec.encode([revision, sourceId, expression.getCanonicalIdentity(), symbol]));
			final requirement:OcamlRuntimeRequirement = {
				id: id + ":runtime",
				sourceKind: RepresentationDecision,
				sourceId: sourceId,
				source: {file: "", min: 0, max: 0},
				semanticCapability: "haxe-nullable-int",
				cause: RepresentationDecision,
				decisionId: id,
				subject: {kind: HaxeType, id: "Null<Int>"},
				implementationFeature: "haxe-nullable-int-v1",
				rootModules: ["HxRuntime"],
				profileEligibility: ["metal", "portable"],
				explanation: "The exact nullable Int operation uses the established null sentinel and checked integer representation."
			};
			final occurrence:OcamlRuntimeUseOccurrence = {
				id: id + ":use",
				planRevision: revision,
				ownerId: ownerIdentity,
				requirementId: requirement.id,
				domain: ExpressionIdentifier,
				exactSymbol: exactSymbol,
				role: "nullable-int:" + expression.path,
				order: occurrences.length,
				source: {
					file: "",
					min: 0,
					max: 0
				},
				profileEligibility: ["metal", "portable"],
				cardinality: 1
			};
			requirements.push(requirement);
			occurrences.push(occurrence);
			usesByPath.set(expression.path, occurrence);
		}
		for (child in expression.copyChildren())
			collect(collection, child);
	}

	/** Only the previously planned symbol at this exact source occurrence may be emitted. **/
	public function reference(expression:OcamlTargetExpressionFact, symbol:String):OcamlRuntimeReference {
		final use = usesByPath.get(expression.path);
		if (use == null)
			throw "Shared target expression has no planned runtime use";
		return authority.expressionIdentifier(use.id, revision, symbol);
	}

	public function reconcile(expression:OcamlExpr):Void
		authority.reconcileExpression(expression);

	/** The caller can record or serialize requirements without mutating this sealed plan. **/
	public function copyRequirements():Array<OcamlRuntimeRequirement> {
		return [
			for (row in requirements)
				{
					id: row.id,
					sourceKind: row.sourceKind,
					sourceId: row.sourceId,
					source: {file: row.source.file, min: row.source.min, max: row.source.max},
					semanticCapability: row.semanticCapability,
					cause: row.cause,
					decisionId: row.decisionId,
					subject: {kind: row.subject.kind, id: row.subject.id},
					implementationFeature: row.implementationFeature,
					rootModules: row.rootModules.copy(),
					profileEligibility: row.profileEligibility.copy(),
					explanation: row.explanation
				}
		];
	}
}
