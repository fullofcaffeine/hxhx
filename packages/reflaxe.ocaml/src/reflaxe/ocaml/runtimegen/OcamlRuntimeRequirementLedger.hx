package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime || eval)
import haxe.Json;
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationContract;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationDecision;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessContract;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessDecision;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerContract;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerDecision;
import reflaxe.ocaml.lowered.OcamlBytesReadModel.OcamlBytesReadContract;
import reflaxe.ocaml.lowered.OcamlBytesReadModel.OcamlBytesReadDecision;
import reflaxe.ocaml.lowered.OcamlBytesRepresentationModel.OcamlBytesRepresentationContract;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationImplicitDefaultPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationNullPolicy;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementCause;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSourceKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSubjectKind;

using StringTools;

/**
	Collects immutable explanations for compatibility-runtime use in one compile.

	Entries are recorded where a target decision is made. Later packaging may read
	the sorted records, but it must not invent or reinterpret why the support is
	needed.
**/
class OcamlRuntimeRequirementLedger {
	public static inline final INT32_ADD = "haxe-int32-add";
	public static inline final ARRAY_ELEMENT_GET = "haxe-array-element-get";
	public static inline final ARRAY_ELEMENT_SET = "haxe-array-element-set";
	public static inline final STRING_NULL_SENTINEL = "haxe-string-null-sentinel";
	public static inline final HAXE_BYTES_MUTATION = OcamlBytesMutationContract.RUNTIME_CAPABILITY;
	public static inline final HAXE_BYTES_ACCESS = OcamlBytesAccessContract.RUNTIME_CAPABILITY;
	public static inline final HAXE_BYTES_PRODUCER = OcamlBytesProducerContract.RUNTIME_CAPABILITY;
	public static inline final HAXE_BYTES_READ = OcamlBytesReadContract.RUNTIME_CAPABILITY;
	public static inline final CORE_RUNTIME = "compiler-core-runtime";
	public static inline final TYPE_REGISTRY = "compiler-type-registry";
	public static inline final TYPE_REGISTRY_DYNAMIC_ARGS = "compiler-type-registry-dynamic-args";
	public static inline final TYPE_REGISTRY_OPTIONAL_NULL = "compiler-type-registry-optional-null";
	public static inline final TYPE_REGISTRY_RUNTIME_UNBOX = "compiler-type-registry-runtime-unbox";
	public static inline final HAXE_STANDARD_IO = "haxe-standard-io";
	public static inline final HAXE_STACK_TRACES = "haxe-stack-traces";
	public static inline final HAXE_FLOAT_BIT_CONVERSIONS = "haxe-float-bit-conversions";

	var currentProgramRevision:Null<String> = null;
	final byId:Map<String, OcamlRuntimeRequirement> = [];

	public function new() {}

	/** Starts one compile and discards every requirement from the prior program. **/
	public function beginProgram(programRevision:String):Void {
		final revision = required(programRevision, "program revision");
		currentProgramRevision = revision;
		byId.clear();
	}

	/** Records one requirement and rejects reused identities with different facts. **/
	public function record(requirement:OcamlRuntimeRequirement):Void {
		if (currentProgramRevision == null)
			throw "OCaml runtime requirements cannot be recorded before the program revision begins.";
		final normalized = normalize(requirement);
		final existing = byId.get(normalized.id);
		if (existing != null) {
			if (Json.stringify(existing) != Json.stringify(normalized))
				throw 'OCaml runtime requirement identity "${normalized.id}" was reused with different facts.';
			return;
		}
		byId.set(normalized.id, normalized);
	}

	/**
		Expands the closed capability IDs on one sealed place plan into complete
		Haxe-expression runtime requirements.
	**/
	public function recordPlacePlan(decisionId:String, originId:String, source:OcamlLoweredSourceSpan, semanticTypeId:String,
			requirementIds:Array<String>):Void {
		for (requirementId in requirementIds) {
			final expectedPrefix = originId + ":runtime:";
			if (!requirementId.startsWith(expectedPrefix))
				throw 'Place runtime requirement "$requirementId" is not scoped to origin "$originId".';
			final capability = requirementId.substr(expectedPrefix.length);
			final implementation = placeImplementation(capability);
			record({
				id: requirementId,
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: originId,
				source: source,
				semanticCapability: capability,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decisionId,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: semanticTypeId
				},
				implementationFeature: implementation.feature,
				rootModules: [implementation.module],
				profileEligibility: ["metal", "portable"],
				explanation: implementation.explanation
			});
		}
	}

	/**
		Records why one sealed non-null Bytes producer needs `HxBytes`.

		The requirement is deliberately occurrence-local. It explains only the
		supported producer result and does not authorize nullable storage,
		receiver calls, indexing, or mutation.
	**/
	public function recordBytesProducer(decision:OcamlBytesProducerDecision):Void {
		OcamlBytesProducerContract.requireDecision(decision);
		final requirementId = decision.id + ":runtime:" + HAXE_BYTES_PRODUCER;
		if (decision.runtimeRequirementIds[0] != requirementId)
			throw 'Bytes producer "${decision.id}" does not name its exact runtime requirement.';
		record({
			id: requirementId,
			sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
			sourceId: decision.id,
			source: decision.source,
			semanticCapability: HAXE_BYTES_PRODUCER,
			cause: OcamlRuntimeRequirementCause.LoweringDecision,
			decisionId: decision.id,
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
				id: OcamlBytesProducerContract.SEMANTIC_TYPE_ID
			},
			implementationFeature: "haxe-bytes-producer-v2",
			rootModules: ["HxBytes"],
			profileEligibility: ["metal", "portable"],
			explanation: 'The sealed ${decision.calleeId} ${decision.kind} operation creates a non-null haxe.io.Bytes value through HxBytes using ${decision.constructionPolicy}; nullable storage, receivers, indexing, and mutation require separate decisions.'
		});
	}

	/**
		Records why one sealed mutating Bytes operation needs `HxBytes`.

		The requirement explains only the exact destination mutation and its
		closed range, overlap, and byte-value policies. It does not authorize
		inline-expanded BytesData operations or other Bytes write families.
	**/
	public function recordBytesMutation(decision:OcamlBytesMutationDecision):Void {
		OcamlBytesMutationContract.requireDecision(decision);
		final requirementId = decision.id + ":runtime:" + HAXE_BYTES_MUTATION;
		if (decision.runtimeRequirementIds[0] != requirementId)
			throw 'Bytes mutation "${decision.id}" does not name its exact runtime requirement.';
		record({
			id: requirementId,
			sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
			sourceId: decision.id,
			source: decision.source,
			semanticCapability: HAXE_BYTES_MUTATION,
			cause: OcamlRuntimeRequirementCause.LoweringDecision,
			decisionId: decision.id,
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
				id: OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID
			},
			implementationFeature: "haxe-bytes-mutation-v1",
			rootModules: ["HxBytes"],
			profileEligibility: ["metal", "portable"],
			explanation: 'The sealed ${decision.calleeId} ${decision.kind} operation mutates one exact haxe.io.Bytes destination through HxBytes after fixing receiver and argument evaluation, range validation, ${decision.overlapPolicy} overlap, and ${decision.valuePolicy} byte behavior; the call returns effect-only Void and does not authorize other write families.'
		});
	}

	/**
		Records why one sealed byte access or data-alias operation needs `HxBytes`.

		The requirement is occurrence-local and carries the already-selected
		bounds, byte-value, mutation, alias, and result policies. It does not
		authorize arbitrary `BytesData` indexing or any other Bytes method.
	**/
	public function recordBytesAccess(decision:OcamlBytesAccessDecision):Void {
		OcamlBytesAccessContract.requireDecision(decision);
		final requirementId = decision.id + ":runtime:" + HAXE_BYTES_ACCESS;
		if (decision.runtimeRequirementIds[0] != requirementId)
			throw 'Bytes access "${decision.id}" does not name its exact runtime requirement.';
		record({
			id: requirementId,
			sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
			sourceId: decision.id,
			source: decision.source,
			semanticCapability: HAXE_BYTES_ACCESS,
			cause: OcamlRuntimeRequirementCause.LoweringDecision,
			decisionId: decision.id,
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
				id: OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID
			},
			implementationFeature: "haxe-bytes-access-v1",
			rootModules: ["HxBytes"],
			profileEligibility: ["metal", "portable"],
			explanation: 'The sealed ${decision.calleeId} ${decision.kind} operation calls HxBytes after fixing ${decision.boundsPolicy} bounds, ${decision.valuePolicy} byte values, ${decision.mutationPolicy} mutation, ${decision.aliasPolicy} aliasing, and ${decision.resultKind} result behavior; other Bytes and BytesData operations require separate decisions.'
		});
	}

	/**
		Records why one sealed read-only Bytes operation needs `HxBytes`.

		The requirement names only the exact read decision. It does not authorize
		indexed access, mutation, nullable materialization, or deferred Float and
		Int64 result families.
	**/
	public function recordBytesRead(decision:OcamlBytesReadDecision):Void {
		OcamlBytesReadContract.requireDecision(decision);
		final requirementId = decision.id + ":runtime:" + HAXE_BYTES_READ;
		if (decision.runtimeRequirementIds[0] != requirementId)
			throw 'Bytes read "${decision.id}" does not name its exact runtime requirement.';
		record({
			id: requirementId,
			sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
			sourceId: decision.id,
			source: decision.source,
			semanticCapability: HAXE_BYTES_READ,
			cause: OcamlRuntimeRequirementCause.LoweringDecision,
			decisionId: decision.id,
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
				id: OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID
			},
			implementationFeature: "haxe-bytes-read-v1",
			rootModules: ["HxBytes"],
			profileEligibility: ["metal", "portable"],
			explanation: 'The sealed ${decision.calleeId} ${decision.kind} operation reads an exact haxe.io.Bytes value through HxBytes after fixing the typed receiver input, its ${decision.receiverConversion} conversion, and argument evaluation order. Exact Null<haxe.io.Bytes> may cross one checked receiver conversion; writes, indexed access, other nullable materialization, and Float or Int64 results require separate decisions.'
		});
	}

	/**
		Returns the closed runtime requirements implied by one sealed program
		representation.

		The first admitted family is exact Haxe `String`. Its OCaml `string`
		carrier can preserve Haxe null only through the canonical value owned by
		`HxString`, so every selected domain records that dependency before
		packaging. Other representation families remain outside this slice.
	**/
	public static function requirementsForRepresentationDecision(decision:OcamlRepresentationDecision):Array<OcamlRuntimeRequirement> {
		if (decision == null)
			throw "OCaml runtime requirement representation decision must not be null.";
		final selectsExactStringSentinel = decision.boxingPolicy == OcamlRepresentationBoxingPolicy.NullableStringCarrier
			|| decision.proof.id == "nullable-string-runtime-sentinel-carrier-v1";
		if (!selectsExactStringSentinel)
			return [];
		if (decision.semanticTypeId != "String"
			|| decision.carrierTypeId != "string"
			|| decision.nullPolicy != OcamlRepresentationNullPolicy.RuntimeSentinel
			|| decision.boxingPolicy != OcamlRepresentationBoxingPolicy.NullableStringCarrier
			|| decision.implicitDefaultPolicy != OcamlRepresentationImplicitDefaultPolicy.RuntimeNullSentinel
			|| decision.proof.id != "nullable-string-runtime-sentinel-carrier-v1") {
			throw 'Representation decision "${decision.id}" does not match the sealed exact String null-sentinel contract.';
		}
		return [
			normalize({
				id: decision.id + ":runtime:" + STRING_NULL_SENTINEL,
				sourceKind: OcamlRuntimeRequirementSourceKind.RepresentationDecision,
				sourceId: decision.id + "@" + decision.revision,
				source: {
					file: "compiler-decision/representation/" + decision.domain,
					min: 0,
					max: 0
				},
				semanticCapability: STRING_NULL_SENTINEL,
				cause: OcamlRuntimeRequirementCause.RepresentationDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: "String"
				},
				implementationFeature: "haxe-string-null-sentinel-v1",
				rootModules: ["HxString"],
				profileEligibility: decision.profileEligibility,
				explanation: "The sealed exact Haxe String carrier uses HxString.hx_null_string to preserve the canonical Haxe null sentinel; this requirement does not claim ownership of other HxString operations."
			})
		];
	}

	/** Records every runtime dependency implied by one sealed representation. **/
	public function recordRepresentationDecision(decision:OcamlRepresentationDecision):Void {
		for (requirement in requirementsForRepresentationDecision(decision))
			record(requirement);
	}

	/** Records one helper required by compiler-generated output or packaging policy. **/
	public function recordCompilerInfrastructure(capability:String):Void {
		final implementation = compilerInfrastructureImplementation(capability);
		record({
			id: implementation.id,
			sourceKind: OcamlRuntimeRequirementSourceKind.CompilerInfrastructure,
			sourceId: implementation.sourceId,
			source: {file: implementation.sourceFile, min: 0, max: 0},
			semanticCapability: capability,
			cause: OcamlRuntimeRequirementCause.CompilerInfrastructure,
			decisionId: implementation.decisionId,
			subject: {
				kind: implementation.subjectKind,
				id: implementation.subjectId
			},
			implementationFeature: implementation.feature,
			rootModules: [implementation.module],
			profileEligibility: ["metal", "portable"],
			explanation: implementation.explanation
		});
	}

	/**
		Records one checked compatibility-runtime need declared by a typed native
		extern boundary.

		The capability selects the runtime implementation. The resolved native
		symbol is checked independently so a misleading declaration cannot make the
		report name a helper that the generated call does not use.
	**/
	public function recordNativeBoundary(capability:String, boundaryId:String, source:OcamlLoweredSourceSpan, nativeSymbol:String):Void {
		final implementation = nativeBoundaryImplementation(capability);
		final stableBoundaryId = required(boundaryId, "native boundary identity");
		final stableNativeSymbol = required(nativeSymbol, 'native symbol for boundary "$stableBoundaryId"');
		final nativeRoot = stableNativeSymbol.split(".")[0];
		if (nativeRoot != implementation.module)
			throw 'Native runtime capability "$capability" requires "${implementation.module}", but boundary "$stableBoundaryId" resolves to "$stableNativeSymbol".';
		record({
			id: "native:" + stableBoundaryId + ":runtime:" + capability,
			sourceKind: OcamlRuntimeRequirementSourceKind.NativeBoundary,
			sourceId: "haxe-declaration:" + stableBoundaryId,
			source: source,
			semanticCapability: capability,
			cause: OcamlRuntimeRequirementCause.NativeBoundary,
			decisionId: "native-boundary:" + stableBoundaryId,
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.NativeBoundary,
				id: stableBoundaryId + " -> " + stableNativeSymbol
			},
			implementationFeature: implementation.feature,
			rootModules: [implementation.module],
			profileEligibility: ["metal", "portable"],
			explanation: implementation.explanation
		});
	}

	/** Returns immutable records in stable identity order. **/
	public function requirementsSorted():Array<OcamlRuntimeRequirement> {
		final out = [for (entry in byId) entry];
		out.sort((left, right) -> compareStrings(left.id, right.id));
		return out;
	}

	/** Returns the deduplicated runtime roots selected by recorded decisions. **/
	public function rootModulesSorted():Array<String> {
		final roots:Map<String, Bool> = [];
		for (entry in byId)
			for (moduleName in entry.rootModules)
				roots.set(moduleName, true);
		final out = [for (moduleName in roots.keys()) moduleName];
		out.sort(compareStrings);
		return out;
	}

	/** Computes a path-stable revision for reports and cache keys. **/
	public function revision():String {
		if (currentProgramRevision == null)
			throw "OCaml runtime requirement revision is unavailable before the program revision begins.";
		return "sha256:" + Sha256.encode(currentProgramRevision + "\n" + Json.stringify(requirementsSorted()));
	}

	static function placeImplementation(capability:String):{feature:String, module:String, explanation:String} {
		return switch (capability) {
			case INT32_ADD:
				{
					feature: "haxe-int32-arithmetic-v1",
					module: "HxInt",
					explanation: "Haxe Int addition has defined 32-bit overflow behavior, so generated OCaml uses the checked HxInt operation."
				};
			case ARRAY_ELEMENT_GET:
				{
					feature: "haxe-array-element-access-v1",
					module: "HxArray",
					explanation: "Reading a Haxe array element must preserve Haxe array bounds, storage, and identity behavior."
				};
			case ARRAY_ELEMENT_SET:
				{
					feature: "haxe-array-element-access-v1",
					module: "HxArray",
					explanation: "Writing a Haxe array element must update the original growable Haxe array using its checked storage contract."
				};
			case _:
				throw 'Unknown place runtime capability "$capability".';
		}
	}

	static function normalize(requirement:OcamlRuntimeRequirement):OcamlRuntimeRequirement {
		if (requirement == null)
			throw "OCaml runtime requirement must not be null.";
		final id = required(requirement.id, "identity");
		final sourceId = required(requirement.sourceId, 'source identity for "$id"');
		final decisionId = required(requirement.decisionId, 'decision identity for "$id"');
		final semanticCapability = required(requirement.semanticCapability, 'semantic capability for "$id"');
		if (requirement.subject == null)
			throw 'OCaml runtime requirement "$id" must name its subject.';
		final subjectKind = validatedSubjectKind(requirement.subject.kind, requirement.sourceKind, id);
		final subjectId = required(requirement.subject.id, 'subject identity for "$id"');
		final implementationFeature = required(requirement.implementationFeature, 'implementation feature for "$id"');
		final explanation = required(requirement.explanation, 'explanation for "$id"');
		if (requirement.source == null || requirement.source.min < 0 || requirement.source.max < requirement.source.min)
			throw 'OCaml runtime requirement "$id" has an invalid source span.';
		final rootModules = normalizedTokens(requirement.rootModules, 'root modules for "$id"');
		if (rootModules.length == 0)
			throw 'OCaml runtime requirement "$id" must name at least one root module.';
		for (moduleName in rootModules)
			if (!~/^[A-Za-z][A-Za-z0-9_]*$/.match(moduleName))
				throw 'OCaml runtime requirement "$id" has invalid root module "$moduleName".';
		final profiles = normalizedTokens(requirement.profileEligibility, 'profiles for "$id"');
		if (profiles.length == 0)
			throw 'OCaml runtime requirement "$id" must name at least one eligible profile.';
		for (profile in profiles)
			if (profile != "metal" && profile != "portable")
				throw 'OCaml runtime requirement "$id" has unsupported profile "$profile".';
		return {
			id: id,
			sourceKind: requirement.sourceKind,
			sourceId: sourceId,
			source: {
				file: OcamlLoweredOrigin.normalizeSourcePath(requirement.source.file),
				min: requirement.source.min,
				max: requirement.source.max
			},
			semanticCapability: semanticCapability,
			cause: requirement.cause,
			decisionId: decisionId,
			subject: {
				kind: subjectKind,
				id: subjectId
			},
			implementationFeature: implementationFeature,
			rootModules: rootModules,
			profileEligibility: profiles,
			explanation: explanation
		};
	}

	static function compilerInfrastructureImplementation(capability:String):{
		id:String,
		sourceId:String,
		sourceFile:String,
		decisionId:String,
		subjectKind:OcamlRuntimeRequirementSubjectKind,
		subjectId:String,
		feature:String,
		module:String,
		explanation:String
	} {
		return switch (capability) {
			case CORE_RUNTIME:
				{
					id: "compiler:runtime-packaging:core",
					sourceId: "compiler-policy:runtime-packaging",
					sourceFile: "compiler-policy/runtime-packaging",
					decisionId: "compiler-runtime:select-core",
					subjectKind: OcamlRuntimeRequirementSubjectKind.CompilerPolicy,
					subjectId: "runtime-packaging",
					feature: "haxe-runtime-core-v1",
					module: "HxRuntime",
					explanation: "Every runtime-enabled project uses HxRuntime as the shared base for compatibility helpers and compiler control values."
				};
			case TYPE_REGISTRY:
				{
					id: "compiler:generated:HxTypeRegistry:type-registry",
					sourceId: "compiler-generated:HxTypeRegistry",
					sourceFile: "compiler-generated/HxTypeRegistry.ml",
					decisionId: "compiler-runtime:emit-type-registry",
					subjectKind: OcamlRuntimeRequirementSubjectKind.GeneratedModule,
					subjectId: "HxTypeRegistry",
					feature: "haxe-type-reflection-registry-v1",
					module: "HxType",
					explanation: "The compiler-generated type registry uses HxType to register classes, enums, constructors, inheritance, and typed-catch identities."
				};
			case TYPE_REGISTRY_DYNAMIC_ARGS:
				{
					id: "compiler:generated:HxTypeRegistry:dynamic-arguments",
					sourceId: "compiler-generated:HxTypeRegistry",
					sourceFile: "compiler-generated/HxTypeRegistry.ml",
					decisionId: "compiler-runtime:emit-reflection-constructor-arguments",
					subjectKind: OcamlRuntimeRequirementSubjectKind.GeneratedModule,
					subjectId: "HxTypeRegistry",
					feature: "haxe-reflection-constructor-arguments-v1",
					module: "HxArray",
					explanation: "Reflection constructors receive Haxe argument arrays, so the generated type registry uses the checked HxArray access contract."
				};
			case TYPE_REGISTRY_OPTIONAL_NULL:
				{
					id: "compiler:generated:HxTypeRegistry:optional-null",
					sourceId: "compiler-generated:HxTypeRegistry",
					sourceFile: "compiler-generated/HxTypeRegistry.ml",
					decisionId: "compiler-runtime:emit-reflection-optional-null",
					subjectKind: OcamlRuntimeRequirementSubjectKind.GeneratedModule,
					subjectId: "HxTypeRegistry",
					feature: "haxe-reflection-optional-arguments-v1",
					module: "HxRuntime",
					explanation: "Missing optional reflection arguments use the target runtime representation of Haxe null."
				};
			case TYPE_REGISTRY_RUNTIME_UNBOX:
				{
					id: "compiler:generated:HxTypeRegistry:runtime-unbox",
					sourceId: "compiler-generated:HxTypeRegistry",
					sourceFile: "compiler-generated/HxTypeRegistry.ml",
					decisionId: "compiler-runtime:emit-reflection-boolean-unbox",
					subjectKind: OcamlRuntimeRequirementSubjectKind.GeneratedModule,
					subjectId: "HxTypeRegistry",
					feature: "haxe-reflection-boolean-argument-unboxing-v1",
					module: "HxRuntime",
					explanation: "Reflection constructors use the checked runtime conversion when a dynamically supplied argument must become a Haxe Bool."
				};
			case _:
				throw 'Unknown compiler runtime capability "$capability".';
		}
	}

	static function nativeBoundaryImplementation(capability:String):{feature:String, module:String, explanation:String} {
		return switch (capability) {
			case HAXE_STANDARD_IO:
				{
					feature: "haxe-standard-io-v1",
					module: "HxStdio",
					explanation: "The typed OCaml standard-I/O facade uses HxStdio to preserve Haxe stream reads, writes, end-of-file behavior, and flushing."
				};
			case HAXE_STACK_TRACES:
				{
					feature: "haxe-stack-traces-v1",
					module: "HxBacktrace",
					explanation: "The typed Haxe stack-trace facades use HxBacktrace to capture OCaml call and exception frames as Haxe arrays of strings."
				};
			case HAXE_FLOAT_BIT_CONVERSIONS:
				{
					feature: "haxe-float-bit-conversions-v1",
					module: "HxFPHelper",
					explanation: "The typed Haxe floating-point facade uses HxFPHelper to convert Float values to and from their exact 32-bit or 64-bit representations."
				};
			case _:
				throw 'Unknown native runtime capability "$capability".';
		}
	}

	static function validatedSubjectKind(kind:OcamlRuntimeRequirementSubjectKind, sourceKind:OcamlRuntimeRequirementSourceKind,
			id:String):OcamlRuntimeRequirementSubjectKind {
		final valid = switch (sourceKind) {
			case HaxeExpression: kind == OcamlRuntimeRequirementSubjectKind.HaxeType;
			case RepresentationDecision: kind == OcamlRuntimeRequirementSubjectKind.HaxeType;
			case CompilerInfrastructure: kind == OcamlRuntimeRequirementSubjectKind.GeneratedModule || kind == OcamlRuntimeRequirementSubjectKind.CompilerPolicy;
			case Configuration: kind == OcamlRuntimeRequirementSubjectKind.CompilerPolicy;
			case NativeBoundary: kind == OcamlRuntimeRequirementSubjectKind.NativeBoundary;
			case RawBoundary: kind == OcamlRuntimeRequirementSubjectKind.RawBoundary;
		};
		if (!valid)
			throw 'OCaml runtime requirement "$id" has subject kind "$kind" that does not match source kind "$sourceKind".';
		return kind;
	}

	static function normalizedTokens(values:Array<String>, label:String):Array<String> {
		if (values == null)
			throw 'OCaml runtime requirement $label must be an array.';
		final out = new Array<String>();
		final seen:Map<String, Bool> = [];
		for (raw in values) {
			final value = required(raw, label);
			if (seen.exists(value))
				throw 'OCaml runtime requirement $label repeats "$value".';
			seen.set(value, true);
			out.push(value);
		}
		out.sort(compareStrings);
		return out;
	}

	static function required(value:String, label:String):String {
		final normalized = value == null ? "" : value.trim();
		if (normalized.length == 0)
			throw 'OCaml runtime requirement $label must not be empty.';
		return normalized;
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
#end
