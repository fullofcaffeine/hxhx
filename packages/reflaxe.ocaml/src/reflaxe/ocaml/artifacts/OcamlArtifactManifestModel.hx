package reflaxe.ocaml.artifacts;

#if (macro || reflaxe_runtime)
/** Closed set of components currently allowed to claim generated OCaml files. **/
enum abstract OcamlArtifactOwner(String) from String to String {
	var ReflaxeFramework = "reflaxe-framework";
	var OcamlCompiler = "ocaml-compiler";
	var DuneProjectEmitter = "dune-project-emitter";
	var RuntimeCopier = "runtime-copier";
	var NativeFunctorEmitter = "native-functor-emitter";
	var PackageAliasEmitter = "package-alias-emitter";
	var LoweringReportWriter = "lowering-report-writer";
	var LifecycleTraceWriter = "lifecycle-trace-writer";
	var MliGenerator = "mli-generator";
	var BuildTimingReportWriter = "build-timing-report-writer";
	var BindingEmitter = "binding-emitter";
	var NativeAdapterEmitter = "native-adapter-emitter";
	var ExportWrapperEmitter = "export-wrapper-emitter";
}

/** Closed file roles used by packaging and inspection. **/
enum abstract OcamlArtifactKind(String) from String to String {
	var HaxeModuleSource = "haxe-module-source";
	var TypeRegistrySource = "type-registry-source";
	var EntrySource = "entry-source";
	var DuneProject = "dune-project";
	var DuneStanza = "dune-stanza";
	var GitIgnore = "gitignore";
	var RuntimeSource = "runtime-source";
	var NativeFunctorSource = "native-functor-source";
	var PackageAliasSource = "package-alias-source";
	var CompilerReport = "compiler-report";
	var InferredInterface = "inferred-interface";
	var GeneratedBinding = "generated-binding";
	var NativeAdapter = "native-adapter";
	var ExportWrapper = "export-wrapper";
}

/** How an artifact's source entered the output transaction. **/
enum abstract OcamlArtifactSourceKind(String) from String to String {
	var Generated = "generated";
	var RepositoryOwned = "repository-owned";
	var CopiedRuntime = "copied-runtime";
	var Inferred = "inferred";
	var GeneratedBinding = "generated-binding";
	var HandwrittenAdapter = "handwritten-adapter";
}

/** Whether content should be reproducible or is expected to vary per run. **/
enum abstract OcamlArtifactStability(String) from String to String {
	var Stable = "stable";
	var Volatile = "volatile";
}

/**
	One compiler-owned file that must exist in a completed OCaml output.

	The claim is recorded by the component that knows why the file exists. The
	manifest builder later verifies the file and computes its digest; it never
	guesses ownership from a generated filename.
**/
typedef OcamlArtifactClaim = {
	final path:String;
	final kind:OcamlArtifactKind;
	final owner:OcamlArtifactOwner;
	final sourceKind:OcamlArtifactSourceKind;
	final sourcePath:Null<String>;
	final license:String;
	final profileEligibility:Array<String>;
	final stability:OcamlArtifactStability;
	final includeInSourceBundle:Bool;
}

/** A verified artifact claim with the bytes observed at manifest sealing. **/
typedef OcamlArtifactEntry = {
	final path:String;
	final kind:String;
	final owner:String;
	final sourceKind:String;
	final sourcePath:Null<String>;
	final license:String;
	final profileEligibility:Array<String>;
	final stability:String;
	final includeInSourceBundle:Bool;
	final sha256:String;
	final bytes:Int;
}

/**
	Whether a prerequisite inventory is authoritative enough for reproducible
	packaging. An incomplete authority remains visible without being mistaken for
	release evidence.
**/
typedef OcamlArtifactAuthority = {
	final status:String;
	final model:String;
	final revision:Null<String>;
	final message:String;
}

/** Machine-readable inventory written beside one completed OCaml output. **/
typedef OcamlArtifactManifestReport = {
	final schemaVersion:Int;
	final model:String;
	final programRevision:String;
	final configurationRevision:String;
	final profile:String;
	final frameworkReceipt:String;
	final entries:Array<OcamlArtifactEntry>;
	final authorities:{
		final semanticRuntime:OcamlArtifactAuthority;
		final nativeDependencies:OcamlArtifactAuthority;
	};
	final summary:{
		final entryCount:Int;
		final sourceBundleEntryCount:Int;
		final volatileEvidenceEntryCount:Int;
		final sourceBundleRevision:String;
		final artifactSetRevision:String;
		final completeForSourceBundle:Bool;
		final blockers:Array<String>;
	};
	final excludedBuildProducts:Array<String>;
}

/** Minimum trusted data used to clean a file owned by the preceding manifest. **/
typedef OcamlPreviousArtifactEntry = {
	final path:String;
	final sha256:String;
}
#end
