package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
#if macro
import haxe.crypto.Sha256;
import haxe.macro.Type.ClassType;
import haxe.macro.TypeTools;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.lowered.OcamlRepresentationModel;
#end

/** Passing a whole class record needs a different proof from optimizing its fields. */
final DOMAIN = "generic-call-value";

final BOXING_POLICY = "nullable-nominal-call-carrier";
final PROOF_ID = "whole-program-generic-class-record-v1";
final PROOF_CLAIM = "The complete program selects one ordinary non-generic class record with no hierarchy, interfaces, native boundary, or dynamic methods. Generic calls preserve that record's identity and nullable reference carrier without interpreting or optimizing its fields.";

#if macro
/**
	Registers only the named record used by ordinary class emission.

	The caller applies the compiler's user-class admission policy first. The
	whole-program inheritance facts must be complete. Field declarations enter
	the revision, but their separate optimized representations are not required:
	this conversion transports the complete object and never reads its fields.
**/
function register(classType:ClassType, context:CompilationContext, representations:OcamlRepresentationRegistry):Void {
	if (!context.virtualTypesComputed || !OcamlMonomorphicClassPlanner.hasDirectRecordLayout(classType, context))
		return;
	switch (classType.kind) {
		case KNormal:
		case _:
			return;
	}
	final semanticTypeId = (classType.pack ?? []).concat([classType.name]).join(".");
	final targetModule = context.ocamlModuleNameForModuleId(classType.module);
	final targetType = context.scopedInstanceTypeName(classType.module, classType.name);
	final fields = [
		for (field in classType.fields.get())
			switch (field.kind) {
				case FVar(_, _):
					field.name + ":" + context.ocamlRecordLabel(field.name) + ":" + TypeTools.toString(field.type);
				case FMethod(_):
					null;
			}
	].filter(value -> value != null);
	final revision = "sha256:" + Sha256.encode([PROOF_ID, semanticTypeId, classType.module, targetModule, targetType].concat(fields).join("|"));
	representations.register({
		semanticTypeId: semanticTypeId,
		domain: GenericCallValue,
		carrierTypeId: targetType,
		nullPolicy: RuntimeSentinel,
		identityPolicy: ReferenceIdentity,
		aliasingPolicy: SharedReferenceAliases,
		storageMutationPolicy: ImmutableBinding,
		valueMutationPolicy: MutableRuntimeContainer,
		boxingPolicy: NullableNominalCallCarrier,
		implicitDefaultPolicy: NotAdmitted,
		reason: "The exact ordinary class record crosses a generic call as one shared reference; its fields remain owned by ordinary class emission.",
		proof: {
			id: PROOF_ID + ":" + revision,
			claim: PROOF_CLAIM
		},
		profileEligibility: ["metal", "portable"],
		nominalTargetModuleName: targetModule,
		nominalTargetTypeName: targetType,
		nominalLayoutRevision: revision
	});
}
#end

#end
