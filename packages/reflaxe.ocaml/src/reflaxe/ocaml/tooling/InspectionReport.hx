package reflaxe.ocaml.tooling;

import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerDecision;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionSnapshot;

/** One runtime module and the current report's reasons for selecting it. **/
typedef InspectionRuntimeReason = {
	final module:String;
	final reasons:Array<String>;
}

/** Reflaxe's receipt for the files emitted by the completed compilation. **/
typedef InspectionGeneratedFiles = {
	final status:String;
	final path:String;
	final schemaVersion:Null<Int>;
	final receiptId:Null<Int>;
	final files:Array<String>;
	final wasCached:Null<Bool>;
	final message:String;
}

/** One category and its number of files in the generated-artifact inventory. **/
typedef InspectionArtifactCount = {
	final id:String;
	final count:Int;
}

/** One prerequisite whose own inventory contributes to packaging trust. **/
typedef InspectionArtifactAuthority = {
	final status:String;
	final model:String;
	final revision:Null<String>;
	final message:String;
}

/**
	The verified ownership and digest summary for every generated OCaml file.

	A present manifest can still report `completeForSourceBundle = false`. That
	means the file inventory itself is sound, while another required inventory—
	such as semantic runtime reasons or locked native dependencies—is unfinished.
**/
typedef InspectionArtifactManifest = {
	final status:String;
	final path:String;
	final schemaVersion:Null<Int>;
	final model:Null<String>;
	final programRevision:Null<String>;
	final configurationRevision:Null<String>;
	final profile:Null<String>;
	final entryCount:Int;
	final sourceBundleEntryCount:Int;
	final volatileEvidenceEntryCount:Int;
	final sourceBundleRevision:Null<String>;
	final artifactSetRevision:Null<String>;
	final completeForSourceBundle:Null<Bool>;
	final semanticRuntime:Null<InspectionArtifactAuthority>;
	final nativeDependencies:Null<InspectionArtifactAuthority>;
	final ownerCounts:Array<InspectionArtifactCount>;
	final kindCounts:Array<InspectionArtifactCount>;
	final blockers:Array<String>;
	final message:String;
}

/** One measured target-owned native build step. **/
typedef InspectionBuildTimingPhase = {
	final id:String;
	final elapsedMilliseconds:Int;
	final exitCode:Int;
}

/**
	Optional target-owned Dune timing tied to the current generated-file receipt.

	Dune typechecking, compilation, and linking remain one measured build phase;
	cache hits, executable loading, startup, and workload runtime are not inferred.
**/
typedef InspectionBuildTiming = {
	final status:String;
	final path:String;
	final schemaVersion:Null<Int>;
	final generatedFilesReceiptId:Null<Int>;
	final mode:Null<String>;
	final duneLayout:Null<String>;
	final target:Null<String>;
	final strict:Null<Bool>;
	final requestedRun:Null<Bool>;
	final mliMode:Null<String>;
	final phases:Array<InspectionBuildTimingPhase>;
	final buildStatus:Null<String>;
	final buildExitCode:Null<Int>;
	final nativeBuildRan:Null<Bool>;
	final duneBuildMilliseconds:Null<Int>;
	final interfaceMilliseconds:Null<Int>;
	final targetRunMilliseconds:Null<Int>;
	final duneBuildIncludes:Array<String>;
	final duneCacheHitsMeasured:Bool;
	final loadSeparated:Bool;
	final startupSeparated:Bool;
	final workloadRuntimeSeparated:Bool;
	final message:String;
}

/** The compiler-owned profile and strict-boundary result for this build. **/
typedef InspectionProfile = {
	final status:String;
	final path:String;
	final schemaVersion:Null<Int>;
	final profile:Null<String>;
	final atomicSemantics:Null<String>;
	final runtimeMode:Null<String>;
	final strictUserBoundaries:Null<Bool>;
	final verifierResult:Null<String>;
	final violationCount:Null<Int>;
	final message:String;
}

/**
	The runtime modules selected by today's compiler/runtime report.

	`semanticManifest` remains false while only core packaging, the generated type
	registry, declared static native boundaries, and typed assignment/update
	operations explain why they need runtime support. The separate partial report
	must not be mistaken for whole-program runtime ownership.
**/
typedef InspectionRuntime = {
	final status:String;
	final path:String;
	final schemaVersion:Null<Int>;
	final profile:Null<String>;
	final runtimeMode:Null<String>;
	final selectionMode:Null<String>;
	final selectedModules:Array<String>;
	final inclusionReasons:Array<InspectionRuntimeReason>;
	final tokenScanFallbackEnabled:Null<Bool>;
	final authority:String;
	final semanticManifest:Bool;
	final message:String;
}

/** A concise view of one sealed typed place operation. **/
typedef InspectionLoweredPlan = {
	final id:String;
	final nodeKind:String;
	final sourceFile:String;
	final sourceMin:Int;
	final sourceMax:Int;
	final sourceOffsetUnit:String;
	final placeKind:Null<String>;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final representationId:Null<String>;
	final representationReason:Null<String>;
	final receiverSemanticTypeId:Null<String>;
	final receiverCarrierTypeId:Null<String>;
	final receiverRepresentationId:Null<String>;
	final indexSemanticTypeId:Null<String>;
	final indexCarrierTypeId:Null<String>;
	final indexRepresentationId:Null<String>;
	final sourceOperator:Null<String>;
	final fixity:Null<String>;
	final conversion:Null<String>;
	final result:Null<String>;
	final effects:Array<String>;
	final schedule:Array<String>;
	final runtimeRequirementIds:Array<String>;
}

/** One exact field carried by an admitted mutable anonymous object. */
typedef InspectionAnonymousStructureField = {
	final name:String;
	final canonicalOrder:Int;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final representationId:String;
	final representationRevision:String;
	final storeConversion:String;
	final loadConversion:String;
}

/**
	The validated runtime shape selected for one anonymous-object family.

	A structure is a name-sorted field layout plus the aliasing and mutation
	rules that generated code must preserve. Source evaluation order is recorded
	on the operation occurrences below because field-name order alone cannot
	explain which initializer runs first.
**/
typedef InspectionAnonymousStructure = {
	final id:String;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final fields:Array<InspectionAnonymousStructureField>;
	final representationId:String;
	final representationRevision:String;
	final representationDomain:String;
	final nullPolicy:String;
	final identityPolicy:String;
	final aliasingPolicy:String;
	final mutationPolicy:String;
	final proofId:String;
	final proofClaim:String;
	final programRevision:String;
	final revision:String;
}

/**
	One validated create, initialize, read, plain write, or compound-write occurrence.

	The evaluation schedule states the observable order explicitly. For example,
	an `Int +=` field update evaluates its receiver once, reads the old value,
	evaluates the right-hand side once, adds with Haxe Int32 behavior, stores the
	new value, and returns that same new value.
**/
typedef InspectionAnonymousStructureOperation = {
	final id:String;
	final occurrenceId:String;
	final sourceFile:String;
	final sourceMin:Int;
	final sourceMax:Int;
	final kind:String;
	final structureId:String;
	final structureRevision:String;
	final structureRepresentationId:String;
	final structureRepresentationRevision:String;
	final fieldName:Null<String>;
	final fieldCanonicalOrder:Int;
	final fieldSourceOrder:Int;
	final fieldSemanticTypeId:String;
	final fieldCarrierTypeId:String;
	final fieldRepresentationId:String;
	final fieldRepresentationRevision:String;
	final storeConversion:Null<String>;
	final loadConversion:Null<String>;
	final fieldOperator:Null<String>;
	final evaluationSchedule:Array<String>;
	final resultSemanticTypeId:String;
	final resultCarrierTypeId:String;
	final resultRepresentationId:String;
	final resultRepresentationRevision:String;
	final runtimeModule:String;
	final runtimeReadOperation:Null<String>;
	final runtimeOperation:String;
	final runtimeRequirementIds:Array<String>;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** One program-owned Haxe-type to OCaml-carrier choice. **/
typedef InspectionRepresentationDecision = {
	final id:String;
	final key:String;
	final programRevision:String;
	final revision:String;
	final semanticTypeId:String;
	final domain:String;
	final carrierTypeId:String;
	final nullPolicy:String;
	final identityPolicy:String;
	final aliasingPolicy:String;
	final storageMutationPolicy:String;
	final valueMutationPolicy:String;
	final boxingPolicy:String;
	final implicitDefaultPolicy:String;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final profileEligibility:Array<String>;
	final nominalTargetModuleName:Null<String>;
	final nominalTargetTypeName:Null<String>;
	final nominalLayoutRevision:Null<String>;
	final arrayDescriptorId:Null<String>;
	final arrayDescriptorRevision:Null<String>;
}

/** One validated direct array shape and its exact element-storage decision. **/
typedef InspectionRepresentedArrayDescriptor = {
	final id:String;
	final key:String;
	final programRevision:String;
	final modelRevision:String;
	final revision:String;
	final arraySemanticTypeId:String;
	final sourceForm:String;
	final closureKind:String;
	final outerWrapperKind:String;
	final elementSemanticTypeId:String;
	final elementRepresentationId:String;
	final elementRepresentationRevision:String;
	final elementCarrierTypeId:String;
	final elementDomain:String;
	final carrierFamilyId:String;
	final arrayCarrierTypeId:String;
	final runtimeCarrierCapabilityId:String;
	final runtimeKindTagId:String;
	final nestingKind:String;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final profileEligibility:Array<String>;
}

/** The admitted portion of the program-wide representation registry. **/
typedef InspectionRepresentation = {
	final status:String;
	final path:String;
	final schemaVersion:Null<Int>;
	final model:Null<String>;
	final revision:Null<String>;
	final decisions:Array<InspectionRepresentationDecision>;
	final representedArrayModel:Null<String>;
	final representedArrayRevision:Null<String>;
	final representedArrays:Array<InspectionRepresentedArrayDescriptor>;
	final scope:String;
	final message:String;
}

/** One occurrence-bound carrier conversion selected before OCaml syntax. **/
typedef InspectionLocalConversion = {
	final id:String;
	final localId:String;
	final role:String;
	final sourceFile:String;
	final sourceMin:Int;
	final sourceMax:Int;
	final inputSemanticTypeId:String;
	final inputCarrierTypeId:String;
	final outputSemanticTypeId:String;
	final outputCarrierTypeId:String;
	final conversion:String;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final profileEligibility:Array<String>;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
	final unsafeOperationId:Null<String>;
}

/** One typed array element whose enum identity is preserved before Dynamic storage. **/
typedef InspectionContainerElementConversion = {
	final id:String;
	final role:String;
	final containerSourceFile:String;
	final containerSourceMin:Int;
	final containerSourceMax:Int;
	final sourceFile:String;
	final sourceMin:Int;
	final sourceMax:Int;
	final containerOrdinal:Int;
	final elementIndex:Int;
	final inputSemanticTypeId:String;
	final inputCarrierTypeId:String;
	final outputSemanticTypeId:String;
	final outputCarrierTypeId:String;
	final conversion:String;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final profileEligibility:Array<String>;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
	final unsafeOperationId:String;
}

/** One admitted unsafe carrier operation and the proof that owns it. **/
typedef InspectionUnsafeOperation = {
	final id:String;
	final conversionId:String;
	final operation:String;
	final sourceFile:String;
	final sourceMin:Int;
	final sourceMax:Int;
	final inputSemanticTypeId:String;
	final inputCarrierTypeId:String;
	final outputSemanticTypeId:String;
	final outputCarrierTypeId:String;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final profileEligibility:Array<String>;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** One directional argument or result crossing selected by the typed call plan. **/
typedef InspectionCallValue = {
	final index:Int;
	final parameterOptional:Bool;
	final inputSemanticTypeId:String;
	final inputCarrierTypeId:String;
	final inputRepresentationId:String;
	final outputSemanticTypeId:String;
	final outputCarrierTypeId:String;
	final outputRepresentationId:String;
	final conversion:String;
	final proofId:String;
	final proofClaim:String;
}

/** One validated source-order action in a sealed typed-call schedule. **/
typedef InspectionCallEvaluationStep = {
	final kind:String;
	final argumentIndex:Null<Int>;
	final sourceArgumentIndex:Null<Int>;
	final slotId:Null<String>;
}

/**
	The standard Haxe `IMap` carrier and operation selected before OCaml syntax.

	This is intentionally separate from a callable boundary: it describes the
	closed standard-library interface slice, not arbitrary user interface
	dispatch.
**/
typedef InspectionStandardIMapCallTarget = {
	final operation:String;
	final keyKind:String;
	final receiverSemanticTypeId:String;
	final receiverCarrierId:String;
	final keySemanticTypeId:String;
	final valueSemanticTypeId:String;
	final argumentSemanticTypeIds:Array<String>;
	final resultSemanticTypeId:String;
	final runtimeModule:String;
	final runtimeFunction:String;
	final resultForm:String;
	final iteratorModule:Null<String>;
	final iteratorFunction:Null<String>;
	final keyStringifier:Null<String>;
	final valueStringifier:Null<String>;
	final runtimeCapabilities:Array<String>;
	final proofId:String;
	final proofClaim:String;
}

/** The exact runtime operation selected for one direct structural Iterator call. */
typedef InspectionStructuralIteratorCallTarget = {
	final operation:String;
	final receiverSemanticTypeId:String;
	final receiverCarrierTypeId:String;
	final resultSemanticTypeId:String;
	final runtimeModule:String;
	final runtimeFunction:String;
	final runtimeCapabilities:Array<String>;
	final proofId:String;
	final proofClaim:String;
}

/**
	One typed decision for a field whose name also appears on `Iterator<T>`.

	The operation says whether the source reads or writes an ordinary stored field,
	or captures a real Iterator method as a function value. Inspection exposes this
	distinction so a successful build cannot hide a return to field-name guessing.
**/
/** One validated stored field, Iterator method capture, or Map-pair projection. **/
typedef InspectionStructuralField = {
	final id:String;
	final occurrenceOrdinal:Int;
	final sourceFile:String;
	final sourceMin:Int;
	final sourceMax:Int;
	final operation:String;
	final fieldName:String;
	final receiverSemanticTypeId:String;
	final receiverCarrierTypeId:String;
	final fieldSemanticTypeId:String;
	final resultSemanticTypeId:String;
	final loadConversion:Null<String>;
	final storeConversion:Null<String>;
	final runtimeModule:String;
	final runtimeOperation:String;
	final runtimeRequirementIds:Array<String>;
	final evaluationSchedule:Array<String>;
	final iteratorTarget:Null<InspectionStructuralIteratorCallTarget>;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** One method proven on a user class before it is adapted to `IMap<K, V>`. */
typedef InspectionIMapInterfaceMethod = {
	final name:String;
	final sourceOwnerModuleId:String;
	final sourceOwnerTypeName:String;
	final argumentSemanticTypeIds:Array<String>;
	final resultSemanticTypeId:String;
}

/** One concrete standard or user map value converted to the shared interface carrier. */
typedef InspectionIMapInterfaceConversion = {
	final id:String;
	final sourceFile:String;
	final sourceMin:Int;
	final sourceMax:Int;
	final role:String;
	final roleIndex:Int;
	final sourceKind:String;
	final sourceSemanticTypeId:String;
	final sourceCarrierTypeId:String;
	final targetSemanticTypeId:String;
	final targetCarrierTypeId:String;
	final keySemanticTypeId:String;
	final valueSemanticTypeId:String;
	final standardKeyKind:Null<String>;
	final keyStringifier:Null<String>;
	final valueStringifier:Null<String>;
	final methods:Array<InspectionIMapInterfaceMethod>;
	final runtimeCapabilities:Array<String>;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** One method call dispatched through an already converted `IMap<K, V>` value. */
typedef InspectionIMapInterfaceCall = {
	final id:String;
	final sourceFile:String;
	final sourceMin:Int;
	final sourceMax:Int;
	final operation:String;
	final receiverSemanticTypeId:String;
	final receiverCarrierTypeId:String;
	final keySemanticTypeId:String;
	final valueSemanticTypeId:String;
	final argumentSemanticTypeIds:Array<String>;
	final resultSemanticTypeId:String;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** One target-owned native Map operation that consumes a proven raw-storage alias. */
typedef InspectionIMapStorageAliasUse = {
	final sourceFile:String;
	final sourceMin:Int;
	final sourceMax:Int;
	final nativeOperation:String;
	final carrierTypeId:String;
}

/**
	One compiler-created `IMap` local that safely keeps its standard Map storage.

	This is not a general `Map` to `IMap` conversion. Every recorded local is a
	closed expansion created by the Haxe standard library, and every read goes
	directly to a matching target-owned native Map operation.
**/
typedef InspectionIMapStorageAlias = {
	final id:String;
	final sourceFile:String;
	final sourceMin:Int;
	final sourceMax:Int;
	final sourceSemanticTypeId:String;
	final sourceCarrierTypeId:String;
	final preservedCarrierTypeId:String;
	final targetSemanticTypeId:String;
	final keySemanticTypeId:String;
	final valueSemanticTypeId:String;
	final standardKeyKind:String;
	final nullPolicy:String;
	final uses:Array<InspectionIMapStorageAliasUse>;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** One typed call occurrence whose target and evaluation order were sealed before syntax. **/
typedef InspectionCall = {
	final id:String;
	final sourceFile:String;
	final sourceMin:Int;
	final sourceMax:Int;
	final calleeId:String;
	final sourceModuleId:String;
	final sourceTypeName:String;
	final sourceFieldName:String;
	final kind:String;
	final receiver:Null<InspectionCallValue>;
	final arguments:Array<InspectionCallValue>;
	final resultKind:String;
	final result:Null<InspectionCallValue>;
	final evaluationSchedule:Array<InspectionCallEvaluationStep>;
	final profileEligibility:Array<String>;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
	final standardIMapTarget:Null<InspectionStandardIMapCallTarget>;
	final structuralIteratorTarget:Null<InspectionStructuralIteratorCallTarget>;
}

/** One callable definition independently sealed against its final body. **/
typedef InspectionCallableBoundary = {
	final id:String;
	final calleeId:String;
	final sourceModuleId:String;
	final sourceTypeName:String;
	final sourceFieldName:String;
	final kind:String;
	final receiver:Null<InspectionCallValue>;
	final arguments:Array<InspectionCallValue>;
	final resultKind:String;
	final result:Null<InspectionCallValue>;
	final profileEligibility:Array<String>;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** One concrete standard comparison selected from the final typed Haxe input. */
typedef InspectionReflectCompare = {
	final id:String;
	final sourceFile:String;
	final sourceMin:Int;
	final sourceMax:Int;
	final domain:String;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/**
	One emitted function's completed result, independent of receiver or arguments.

	This boundary can reuse a broader callable boundary or come from the first
	declaration-only exact-Int slice. Its presence does not mean new call sites are
	admitted.
**/
typedef InspectionFunctionResultBoundary = {
	final id:String;
	final source:String;
	final callableBoundaryId:Null<String>;
	final sourceModuleId:String;
	final sourceTypeName:String;
	final sourceFieldName:String;
	final resultKind:String;
	final result:Null<InspectionCallValue>;
	final anonymousStructure:Null<InspectionFunctionResultAnonymousStructureProof>;
	final profileEligibility:Array<String>;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** Exact anonymous-object structure and representation reused by a function result. **/
typedef InspectionFunctionResultAnonymousStructureProof = {
	final semanticTypeId:String;
	final structureId:String;
	final structureRevision:String;
	final structureProofId:String;
	final representationId:String;
	final representationRevision:String;
}

/** One report-safe reference to the program-owned nominal class layout. **/
typedef InspectionControlNominalRepresentationProof = {
	final targetModuleName:String;
	final targetTypeName:String;
	final layoutRevision:String;
	final representationProofId:String;
}

/** The exact value crossing carried by one private compiler-control signal. **/
typedef InspectionControlPayload = {
	final inputSemanticTypeId:String;
	final inputCarrierTypeId:String;
	final inputRepresentationId:String;
	final signalCarrierTypeId:String;
	final outputSemanticTypeId:String;
	final outputCarrierTypeId:String;
	final outputRepresentationId:String;
	final representationRevision:Null<String>;
	final arrayDescriptorId:Null<String>;
	final arrayDescriptorRevision:Null<String>;
	final arrayLiteralProducerId:Null<String>;
	final arrayLiteralProducerPlanRevision:Null<String>;
	final conversion:String;
	final nominalRepresentation:Null<InspectionControlNominalRepresentationProof>;
	final proofId:String;
	final proofClaim:String;
}

/** One lexical loop target sealed before break/continue syntax is emitted. **/
typedef InspectionControlLoopTarget = {
	final id:String;
	final sourceFile:String;
	final sourceMin:Int;
	final sourceMax:Int;
	final kind:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
	final proofId:String;
	final proofClaim:String;
}

/** One function, loop, or Haxe exception transfer sealed before OCaml syntax. **/
typedef InspectionControl = {
	final id:String;
	final sourceFile:String;
	final sourceMin:Int;
	final sourceMax:Int;
	final kind:String;
	final effect:String;
	final targetKind:String;
	final targetId:String;
	final payload:Null<InspectionControlPayload>;
	final runtimeTags:Array<String>;
	final runtimeTagPolicy:String;
	final mechanism:String;
	final runtimeCapabilityId:String;
	final profileEligibility:Array<String>;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** One represented primitive, monomorphic class, or Dynamic catch binding. **/
typedef InspectionControlCatchClause = {
	final id:String;
	final sourceFile:String;
	final sourceMin:Int;
	final sourceMax:Int;
	final order:Int;
	final variableName:String;
	final semanticTypeId:String;
	final signalCarrierTypeId:String;
	final outputCarrierTypeId:String;
	final outputRepresentationId:String;
	final matchPolicy:String;
	final runtimeTag:Null<String>;
	final conversion:String;
	final nominalRepresentation:Null<InspectionControlNominalRepresentationProof>;
	final bodyResultPolicy:String;
	final effects:Array<String>;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** One complete source-ordered catch chain sealed before OCaml syntax. **/
typedef InspectionControlCatchChain = {
	final id:String;
	final sourceFile:String;
	final sourceMin:Int;
	final sourceMax:Int;
	final clauses:Array<InspectionControlCatchClause>;
	final tryBodyResultPolicy:String;
	final inputChannels:Array<String>;
	final targetNativeRuntimeTags:Array<String>;
	final haxeUnmatchedPolicy:String;
	final targetNativeUnmatchedPolicy:String;
	final privateControlPolicy:String;
	final runtimeCapabilityId:String;
	final profileEligibility:Array<String>;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** One mutable static cell selected before generated type values are emitted. **/
typedef InspectionStaticStorageEntry = {
	final id:String;
	final key:String;
	final initializationId:String;
	final programRevision:String;
	final revision:String;
	final moduleId:String;
	final ownerTypeName:String;
	final fieldName:String;
	final targetValueName:String;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final kind:String;
	final declarationSite:String;
	final declarationTypeName:Null<String>;
	final declarationTypeOrder:Int;
	final ownerTypeOrder:Int;
	final declarationOrder:Int;
	final initializationOrder:Int;
	final hasInitializer:Bool;
	final initializerDependencyKeys:Array<String>;
	final representationId:Null<String>;
}

/** Optional report for the assignment/update family already on typed lowering. **/
typedef InspectionLowering = {
	final status:String;
	final required:Bool;
	final path:String;
	final schemaVersion:Null<Int>;
	final model:Null<String>;
	final admittedInputRevision:Null<String>;
	final plans:Array<InspectionLoweredPlan>;
	final representation:InspectionRepresentation;
	final arrayLiteralProducerModel:Null<String>;
	final arrayLiteralProducerRevision:Null<String>;
	final arrayLiteralProducers:Array<OcamlArrayLiteralProducerDecision>;
	final anonymousStructureRevision:Null<String>;
	final anonymousStructures:Array<InspectionAnonymousStructure>;
	final anonymousStructureOperations:Array<InspectionAnonymousStructureOperation>;
	final structuralFieldRevision:Null<String>;
	final structuralFields:Array<InspectionStructuralField>;
	final iMapInterfaceRevision:Null<String>;
	final iMapInterfaceConversions:Array<InspectionIMapInterfaceConversion>;
	final iMapInterfaceCalls:Array<InspectionIMapInterfaceCall>;
	final iMapStorageAliases:Array<InspectionIMapStorageAlias>;
	final localConversionRevision:Null<String>;
	final localConversions:Array<InspectionLocalConversion>;
	final containerElementRequiredConversionRevision:Null<String>;
	final containerElementRequiredConversionIds:Array<String>;
	final containerElementConversionRevision:Null<String>;
	final containerElementConversions:Array<InspectionContainerElementConversion>;
	final unsafeOperationCompleteness:Null<String>;
	final unsafeOperationRevision:Null<String>;
	final unsafeOperations:Array<InspectionUnsafeOperation>;
	final callRevision:Null<String>;
	final calls:Array<InspectionCall>;
	final callableBoundaries:Array<InspectionCallableBoundary>;
	final reflectCompareRevision:Null<String>;
	final reflectCompare:Array<InspectionReflectCompare>;
	final functionResultBoundaryRevision:Null<String>;
	final functionResultBoundaries:Array<InspectionFunctionResultBoundary>;
	final controlRevision:Null<String>;
	final controls:Array<InspectionControl>;
	final controlCatchRevision:Null<String>;
	final controlCatches:Array<InspectionControlCatchChain>;
	final controlTargetRevision:Null<String>;
	final controlTargets:Array<InspectionControlLoopTarget>;
	final controlAdmissionRevision:Null<String>;
	final controlAdmissions:Array<OcamlControlAdmissionSnapshot>;
	final staticStorageRevision:Null<String>;
	final staticStorage:Array<InspectionStaticStorageEntry>;
	final scope:String;
	final message:String;
}

/** A future inspection family whose typed owner is not implemented yet. **/
typedef InspectionUnavailableCapability = {
	final id:String;
	final label:String;
	final status:String;
	final reason:String;
}

/** Aggregate result used by the CLI and automation. **/
typedef InspectionSummary = {
	final valid:Bool;
	final exitCode:Int;
	final errorCount:Int;
	final generatedFileCount:Int;
	final artifactEntryCount:Int;
	final runtimeModuleCount:Int;
	final loweredPlanCount:Int;
	final representationDecisionCount:Int;
	final representedArrayCount:Int;
	final arrayLiteralProducerCount:Int;
	final anonymousStructureCount:Int;
	final anonymousStructureOperationCount:Int;
	final structuralFieldCount:Int;
	final iMapInterfaceConversionCount:Int;
	final iMapInterfaceCallCount:Int;
	final iMapStorageAliasCount:Int;
	final localConversionCount:Int;
	final containerElementConversionCount:Int;
	final unsafeOperationCount:Int;
	final callCount:Int;
	final callableBoundaryCount:Int;
	final reflectCompareCount:Int;
	final functionResultBoundaryCount:Int;
	final controlCount:Int;
	final controlCatchCount:Int;
	final controlTargetCount:Int;
	final controlAdmissionCount:Int;
	final staticStorageCount:Int;
}

/**
	Stable machine-readable output from `reflaxe.ocaml inspect --json`.

	This schema summarizes only compiler-owned artifacts. It deliberately keeps
	future semantic manifests visible as unavailable instead of reconstructing
	them from generated OCaml or Dune text.
**/
typedef InspectionReport = {
	final schemaVersion:Int;
	final projectRoot:String;
	final outputDirectory:String;
	final generatedFiles:InspectionGeneratedFiles;
	final artifactManifest:InspectionArtifactManifest;
	final buildTiming:InspectionBuildTiming;
	final profile:InspectionProfile;
	final runtime:InspectionRuntime;
	final lowering:InspectionLowering;
	final representation:InspectionRepresentation;
	final consistencyErrors:Array<String>;
	final unavailable:Array<InspectionUnavailableCapability>;
	final summary:InspectionSummary;
}
