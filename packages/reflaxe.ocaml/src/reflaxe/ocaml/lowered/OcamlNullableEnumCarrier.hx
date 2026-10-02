package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.lowered.OcamlNativeEnumRepresentation.OcamlNativeEnumDescriptor;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationAliasingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationIdentityPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationImplicitDefaultPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationNullPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationStorageMutationPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationValueMutationPolicy;

/**
	The detached evidence for one exact native-enum value entering `Null<Enum>`.

	The descriptor identifies the generated OCaml variant. The two representation
	revisions bind that variant to the request-owned input and `Obj.t` output
	decisions. Keeping these facts together prevents result, control, report, and
	syntax consumers from reconstructing different carriers for the same crossing.
**/
typedef OcamlNullableEnumCarrierReference = {
	final modelRevision:String;
	final revision:String;
	final descriptor:OcamlNativeEnumDescriptor;
	final inputRepresentationId:String;
	final inputRepresentationRevision:String;
	final outputRepresentationId:String;
	final outputRepresentationRevision:String;
	final programRevision:String;
	final crossingModel:String;
	final crossingRevision:String;
}

/** Builds and checks nullable-enum carrier evidence without retaining macro objects. */
class OcamlNullableEnumCarrier {
	public static inline final MODEL_REVISION = "ocaml-nullable-enum-carrier-reference-v1";
	public static inline final CROSSING_MODEL = "ocaml-native-enum-to-nullable-result-v1";

	/** Binds one current descriptor to the registry-owned input and output decisions. */
	public static function create(descriptor:OcamlNativeEnumDescriptor, input:OcamlRepresentationDecision, output:OcamlRepresentationDecision,
			programRevision:String, context:CompilationContext):OcamlNullableEnumCarrierReference {
		OcamlNativeEnumRepresentation.requireCurrent(descriptor, context);
		requireDecisionPair(descriptor, input, output, programRevision);
		final crossingRevision = crossingFingerprint(descriptor, input.id, input.revision, output.id, output.revision, programRevision);
		final reference:OcamlNullableEnumCarrierReference = {
			modelRevision: MODEL_REVISION,
			revision: "",
			descriptor: copyDescriptor(descriptor),
			inputRepresentationId: input.id,
			inputRepresentationRevision: input.revision,
			outputRepresentationId: output.id,
			outputRepresentationRevision: output.revision,
			programRevision: programRevision,
			crossingModel: CROSSING_MODEL,
			crossingRevision: crossingRevision
		};
		return withRevision(reference);
	}

	/** Returns a detached copy for sealed plans and reports. */
	public static function copy(reference:OcamlNullableEnumCarrierReference):OcamlNullableEnumCarrierReference {
		return {
			modelRevision: reference.modelRevision,
			revision: reference.revision,
			descriptor: copyDescriptor(reference.descriptor),
			inputRepresentationId: reference.inputRepresentationId,
			inputRepresentationRevision: reference.inputRepresentationRevision,
			outputRepresentationId: reference.outputRepresentationId,
			outputRepresentationRevision: reference.outputRepresentationRevision,
			programRevision: reference.programRevision,
			crossingModel: reference.crossingModel,
			crossingRevision: reference.crossingRevision
		};
	}

	/** Recomputes every detached leaf without consulting request-local registries. */
	public static function requireShape(reference:OcamlNullableEnumCarrierReference):Void {
		if (reference == null)
			throw "reflaxe.ocaml [ocaml-nullable-enum:missing-reference]: nullable enum carrier evidence is missing";
		OcamlNativeEnumRepresentation.validate(reference.descriptor);
		final semanticTypeId = reference.descriptor.semanticTypeId;
		final nullableSemanticTypeId = 'Null<$semanticTypeId>';
		final expectedInput = 'representation:$semanticTypeId:internal-value';
		final expectedOutput = 'representation:$nullableSemanticTypeId:internal-value';
		final expectedCrossing = crossingFingerprint(reference.descriptor, reference.inputRepresentationId, reference.inputRepresentationRevision,
			reference.outputRepresentationId, reference.outputRepresentationRevision, reference.programRevision);
		if (reference.modelRevision != MODEL_REVISION
			|| reference.programRevision.length == 0
			|| reference.inputRepresentationId != expectedInput
			|| reference.outputRepresentationId != expectedOutput
			|| !StringTools.startsWith(reference.inputRepresentationRevision, "sha256:")
			|| !StringTools.startsWith(reference.outputRepresentationRevision, "sha256:")
			|| reference.crossingModel != CROSSING_MODEL
			|| reference.crossingRevision != expectedCrossing
			|| reference.revision != revision(reference)) {
			throw "reflaxe.ocaml [ocaml-nullable-enum:invalid-reference]: nullable enum carrier evidence changed after planning";
		}
	}

	/** Rejoins detached evidence to the active naming context and representation registry. */
	public static function requireCurrent(reference:OcamlNullableEnumCarrierReference, context:CompilationContext,
			representations:OcamlRepresentationRegistry):Void {
		requireShape(reference);
		OcamlNativeEnumRepresentation.requireCurrent(reference.descriptor, context);
		final input = representations.require(reference.inputRepresentationId, reference.programRevision);
		final output = representations.require(reference.outputRepresentationId, reference.programRevision);
		if (input.revision != reference.inputRepresentationRevision || output.revision != reference.outputRepresentationRevision)
			throw "reflaxe.ocaml [ocaml-nullable-enum:stale-representation]: nullable enum carrier revisions no longer match the active program";
		requireDecisionPair(reference.descriptor, input, output, reference.programRevision);
	}

	/** Returns the complete deterministic identity used by enclosing plan fingerprints. */
	public static function fingerprint(reference:OcamlNullableEnumCarrierReference):String {
		requireShape(reference);
		return reference.revision;
	}

	public static function same(left:OcamlNullableEnumCarrierReference, right:OcamlNullableEnumCarrierReference):Bool {
		return fingerprint(left) == fingerprint(right);
	}

	static function requireDecisionPair(descriptor:OcamlNativeEnumDescriptor, input:OcamlRepresentationDecision, output:OcamlRepresentationDecision,
			programRevision:String):Void {
		final nullableSemanticTypeId = 'Null<${descriptor.semanticTypeId}>';
		if (input.programRevision != programRevision
			|| input.semanticTypeId != descriptor.semanticTypeId
			|| input.domain != OcamlRepresentationDomain.InternalValue
			|| input.carrierTypeId != descriptor.targetTypeName
			|| input.nullPolicy != OcamlRepresentationNullPolicy.NonNull
			|| input.identityPolicy != OcamlRepresentationIdentityPolicy.ReferenceIdentity
			|| input.aliasingPolicy != OcamlRepresentationAliasingPolicy.SharedReferenceAliases
			|| input.storageMutationPolicy != OcamlRepresentationStorageMutationPolicy.ImmutableBinding
			|| input.valueMutationPolicy != OcamlRepresentationValueMutationPolicy.ImmutableValue
			|| input.boxingPolicy != OcamlRepresentationBoxingPolicy.DirectNativeEnumCarrier
			|| input.implicitDefaultPolicy != OcamlRepresentationImplicitDefaultPolicy.NotAdmitted
			|| input.nominalTargetModuleName != descriptor.targetModuleName
			|| input.nominalTargetTypeName != descriptor.targetTypeName
			|| input.nominalLayoutRevision != descriptor.revision
			|| output.programRevision != programRevision
			|| output.semanticTypeId != nullableSemanticTypeId
			|| output.domain != OcamlRepresentationDomain.InternalValue
			|| output.carrierTypeId != "Obj.t"
			|| output.nullPolicy != OcamlRepresentationNullPolicy.RuntimeSentinel
			|| output.identityPolicy != OcamlRepresentationIdentityPolicy.ReferenceIdentity
			|| output.aliasingPolicy != OcamlRepresentationAliasingPolicy.SharedReferenceAliases
			|| output.storageMutationPolicy != OcamlRepresentationStorageMutationPolicy.ImmutableBinding
			|| output.valueMutationPolicy != OcamlRepresentationValueMutationPolicy.ImmutableValue
			|| output.boxingPolicy != OcamlRepresentationBoxingPolicy.DirectRuntimeContainer
			|| output.implicitDefaultPolicy != OcamlRepresentationImplicitDefaultPolicy.NotAdmitted) {
			throw "reflaxe.ocaml [ocaml-nullable-enum:representation-mismatch]: nullable enum carrier evidence does not match its registry decisions";
		}
	}

	static function withRevision(reference:OcamlNullableEnumCarrierReference):OcamlNullableEnumCarrierReference {
		return {
			modelRevision: reference.modelRevision,
			revision: revision(reference),
			descriptor: copyDescriptor(reference.descriptor),
			inputRepresentationId: reference.inputRepresentationId,
			inputRepresentationRevision: reference.inputRepresentationRevision,
			outputRepresentationId: reference.outputRepresentationId,
			outputRepresentationRevision: reference.outputRepresentationRevision,
			programRevision: reference.programRevision,
			crossingModel: reference.crossingModel,
			crossingRevision: reference.crossingRevision
		};
	}

	static function crossingFingerprint(descriptor:OcamlNativeEnumDescriptor, inputId:String, inputRevision:String, outputId:String, outputRevision:String,
			programRevision:String):String {
		return hash([
			CROSSING_MODEL,
			descriptor.revision,
			inputId,
			inputRevision,
			outputId,
			outputRevision,
			programRevision
		]);
	}

	static function revision(reference:OcamlNullableEnumCarrierReference):String {
		return hash([
			MODEL_REVISION,
			reference.descriptor.revision,
			reference.inputRepresentationId,
			reference.inputRepresentationRevision,
			reference.outputRepresentationId,
			reference.outputRepresentationRevision,
			reference.programRevision,
			reference.crossingModel,
			reference.crossingRevision
		]);
	}

	static function hash(fields:Array<String>):String {
		return "sha256:" + Sha256.encode([for (field in fields) field.length + ":" + field].join(""));
	}

	static function copyDescriptor(descriptor:OcamlNativeEnumDescriptor):OcamlNativeEnumDescriptor {
		return {
			semanticTypeId: descriptor.semanticTypeId,
			sourceModuleId: descriptor.sourceModuleId,
			sourceTypeName: descriptor.sourceTypeName,
			targetModuleName: descriptor.targetModuleName,
			targetTypeName: descriptor.targetTypeName,
			revision: descriptor.revision
		};
	}
}
#end
