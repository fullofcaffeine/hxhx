package reflaxe.ocaml.tooling;

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
	final mutationPolicy:String;
	final boxingPolicy:String;
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
	final scope:String;
	final message:String;
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
