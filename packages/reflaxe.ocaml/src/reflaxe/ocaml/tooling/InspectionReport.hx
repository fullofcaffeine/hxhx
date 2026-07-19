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

	`semanticManifest` remains false until the locked, source-rooted runtime
	ledger described by the architecture plan is implemented.
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
	final sourceOperator:Null<String>;
	final fixity:Null<String>;
	final conversion:Null<String>;
	final result:Null<String>;
	final effects:Array<String>;
	final schedule:Array<String>;
	final runtimeRequirementIds:Array<String>;
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
	final runtimeModuleCount:Int;
	final loweredPlanCount:Int;
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
	final buildTiming:InspectionBuildTiming;
	final profile:InspectionProfile;
	final runtime:InspectionRuntime;
	final lowering:InspectionLowering;
	final consistencyErrors:Array<String>;
	final unavailable:Array<InspectionUnavailableCapability>;
	final summary:InspectionSummary;
}
