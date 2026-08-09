package reflaxe.ocaml;

#if (macro || reflaxe_runtime)
import haxe.io.Bytes;
import haxe.io.Path;
import haxe.ds.ObjectMap;
#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.macros.StrictModeEnforcer;
import sys.io.File;
import sys.io.FileOutput;
#end
import haxe.macro.Type;
import haxe.macro.Type.TConstant;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import reflaxe.DirectToStringCompiler;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;
import reflaxe.lifecycle.FinalProgramFingerprintSnapshot;
import reflaxe.lifecycle.LexicalLocalIdentityPlan;
import reflaxe.lifecycle.TargetReuseCatalog;
import reflaxe.lifecycle.TargetReuseRequestOutcome;
import reflaxe.lifecycle.TargetReuseRevisionComponent;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.artifacts.OcamlArtifactConfigurationRevision;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestBuilder;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactAuthority;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactOwner;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactSourceKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactStability;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestSchema;
import reflaxe.ocaml.artifacts.OcamlSourceBundleAuthority;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlBuilder;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlSourcePositionMapper;
import reflaxe.ocaml.ast.OcamlModuleItem;
import reflaxe.ocaml.ast.OcamlLetBinding;
import reflaxe.ocaml.ast.OcamlAssignOp;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.ast.OcamlRecordField;
import reflaxe.ocaml.ast.OcamlTypeDecl;
import reflaxe.ocaml.ast.OcamlTypeDeclKind;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.ast.OcamlTypeRecordField;
import reflaxe.ocaml.ast.OcamlVariantConstructor;
import reflaxe.ocaml.runtimegen.DuneProjectEmitter;
import reflaxe.ocaml.runtimegen.DuneProjectEmitter.DuneProjectConfig;
import reflaxe.ocaml.runtimegen.OcamlBuildRunner;
import reflaxe.ocaml.runtimegen.OcamlBuildTimingReport.OcamlBuildTimingReportWriter;
import reflaxe.ocaml.runtimegen.OcamlCheckedGeneratedText;
import reflaxe.ocaml.runtimegen.OcamlDuneBuildState;
import reflaxe.ocaml.runtimegen.OcamlNativeFunctorEmitter;
import reflaxe.ocaml.runtimegen.PackageAliasEmitter;
import reflaxe.ocaml.runtimegen.RuntimeCopier;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifest;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifestModel.RuntimeSourceManifestSnapshot;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryClassFields;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryClassSuper;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryClassTags;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryEmptyConstructor;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryEnumLayout;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryProgramIdentifier;
import reflaxe.ocaml.runtimegen.OcamlTypeRegistryBaseEmitter.OcamlTypeRegistryRuntimeUse;
import reflaxe.ocaml.runtimegen.RuntimeUsageCollector;
import reflaxe.ocaml.reuse.OcamlTargetReuseContract;
import reflaxe.ocaml.reuse.OcamlTargetReuseContract.OcamlTargetReuseObservation;
import reflaxe.ocaml.reuse.OcamlTargetImplementationRevision;
import reflaxe.ocaml.reuse.OcamlTargetReusePhaseReportWriter;
import reflaxe.ocaml.reuse.OcamlTargetReuseTestHooks;
import reflaxe.ocaml.reuse.OcamlSourceBundleCandidate;
import reflaxe.ocaml.reuse.OcamlSourceBundleCandidate.OcamlSourceBundlePackResult;
import reflaxe.ocaml.reuse.OcamlSourceBundleReplay;
import reflaxe.ocaml.reuse.OcamlSourceBundleReplay.OcamlSourceBundleReplayCorruption;
import reflaxe.ocaml.lowered.OcamlLoweringReportWriter;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableBoundaryPlan;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry.OcamlSealedStandaloneExpressionPlan;
import reflaxe.ocaml.lowered.OcamlFunctionPlanSealer;
import reflaxe.ocaml.lowered.OcamlFieldRepresentationMaterializer;
import reflaxe.ocaml.lowered.OcamlFieldRepresentationMaterializer.OcamlFieldRepresentationMaterialization;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlanner;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;
import reflaxe.ocaml.lowered.OcamlMonomorphicClassPlanner;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlStaticStoragePlan;
import reflaxe.ocaml.lowered.OcamlStaticStoragePlan.OcamlStaticStorageDeclarationSite;
import reflaxe.ocaml.lowered.OcamlStaticStoragePlan.OcamlStaticStorageEntry;
import reflaxe.ocaml.lowered.OcamlStaticStoragePlan.OcamlStaticStorageKind;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapCallContract;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapKeyKind;
import reflaxe.ocaml.lowered.OcamlStandardMapCarrierModel.OcamlStandardMapCarrierContract;
import reflaxe.ocaml.lowered.OcamlStringRepresentationMaterializer;
import reflaxe.ocaml.lifecycle.OcamlSemanticLifecycleTraceWriter;
import reflaxe.GenericCompiler;
import reflaxe.lifecycle.ProgramRevision;
import reflaxe.output.DataAndFileInfo;
import reflaxe.ocaml.OcamlNameTools;

using StringTools;
using reflaxe.helpers.BaseTypeHelper;

private typedef PendingPublishedOutputBuild = {
	final publicDirectory:String;
	final buildDirectory:String;
	final exeName:String;
	final mode:String;
	final duneLayout:Null<String>;
	final run:Bool;
	final strict:Bool;
	final timingReport:Bool;
	final artifacts:OcamlArtifactManifestBuilder;
}

/**
 * Minimal OCaml compiler scaffold.
 *
 * Milestone 0 goal: register with Reflaxe and emit at least one `.ml` file.
 * Later milestones replace string stubs with a real OCaml IR pipeline.
 */
class OcamlCompiler extends DirectToStringCompiler {
	public static var instance:OcamlCompiler;

	public final functionPlanRegistry:OcamlFunctionPlanRegistry = new OcamlFunctionPlanRegistry();
	public final representationRegistry:OcamlRepresentationRegistry = new OcamlRepresentationRegistry();
	public final staticStoragePlan:OcamlStaticStoragePlan = new OcamlStaticStoragePlan();

	final ctx:CompilationContext = new CompilationContext();
	final printer:OcamlASTPrinter = new OcamlASTPrinter();
	var mainModuleId:Null<String> = null;
	final staticMainCandidateModules:Array<String> = [];
	final staticMainCandidateFileIdByModule = new haxe.ds.StringMap<String>();
	final staticMainCandidateClassNameByModule = new haxe.ds.StringMap<String>();
	var checkedOutputCollisions:Bool = false;
	var pendingPublishedOutputBuild:Null<PendingPublishedOutputBuild>;
	var targetReuseObservation:Null<OcamlTargetReuseObservation>;
	var targetReuseRuntimeSourceManifest:Null<RuntimeSourceManifestSnapshot>;
	var stagedTargetReuseCandidate:Null<OcamlSourceBundleCandidate>;
	var targetRevisionObservationMilliseconds:Int = 0;
	var targetMissPreparationMilliseconds:Int = 0;
	var targetReuseLookupMilliseconds:Int = 0;
	var targetReusePayloadValidationMilliseconds:Int = 0;
	var targetReplayFilesMilliseconds:Int = 0;
	var targetReplayReceiptAndManifestMilliseconds:Int = 0;
	var targetReuseLookupRan:Bool = false;
	var targetMissPreparationRan:Bool = false;
	var targetReplaySucceeded:Bool = false;
	var targetReusePayloadBytes:Null<Int>;
	var skippedTargetGenerationWarnings:Int = 0;
	var semanticRuntimeAuthority:Null<OcamlArtifactAuthority>;
	var nativeSourceDeclarationAuthority:Null<OcamlArtifactAuthority>;
	final compilerExpressionOrdinals:ObjectMap<TypedExpr, Int> = new ObjectMap();
	var nextCompilerExpressionOrdinal:Int = 0;

	#if macro
	/**
		Opt-in progress/profiling logs for large stage0 builds.

		Why
		- When compiling large compiler-shaped programs (notably `packages/hxhx`) the stage0 Haxe
		  invocation can take a long time and produce no on-disk output until late in codegen.
		- That makes snapshot refreshes look “stuck” even when they’re just busy.

		What
		- If either define is set:
		  - `-D reflaxe_ocaml_progress`
		  - `-D reflaxe_ocaml_telemetry`
		  we emit periodic `Context.warning(...)` messages with counts + elapsed time.

		Notes
		- Keep this coarse and opt-in so normal CI/user builds remain quiet.
	**/
	var profileEnabled:Bool = false;

	var profileStartS:Float = 0.0;
	var profileLastS:Float = 0.0;
	var profClassCount:Int = 0;
	var profEnumCount:Int = 0;
	var profileVerbose:Bool = false;
	var profileClassFilter:Null<String> = null;
	var profileFieldFilter:Null<String> = null;
	var profileDetail:Bool = false;
	var profileModulePrepareStartS:Float = 0.0;
	var profileModulePrepareName:Null<String> = null;
	var pendingStaticStorageModuleOrder:Array<String> = [];
	var pendingStaticStorageClassesByModule:Map<String, Array<ClassType>> = [];

	static var profileLog:Null<FileOutput> = null;
	static var profileLogPath:Null<String> = null;

	inline function profileNowS():Float
		return haxe.Timer.stamp();

	function profileTryOpenLog():Void {
		try {
			final path = Sys.getEnv("REFLAXE_OCAML_PROGRESS_FILE");
			if (path == null || path.length == 0)
				return;
			if (profileLog != null && profileLogPath == path)
				return;
			// If the path changes mid-build, close the previous handle best-effort.
			if (profileLog != null) {
				try
					profileLog.close()
				catch (_:Dynamic) {}
			}
			profileLogPath = path;
			profileLog = File.append(path, false);
		} catch (_:Dynamic) {}
	}

	function profileLogLine(msg:String):Void {
		if (!profileEnabled)
			return;
		profileTryOpenLog();
		if (profileLog == null)
			return;
		try {
			profileLog.writeString(msg + "\n");
			profileLog.flush();
		} catch (_:Dynamic) {}
	}

	function profileInit():Void {
		if (!profileEnabled || profileStartS != 0.0)
			return;
		profileStartS = profileNowS();
		profileLastS = profileStartS;
		final msg = "reflaxe.ocaml: progress logging enabled (-D reflaxe_ocaml_progress/-D reflaxe_ocaml_telemetry)";
		Context.warning(msg, Context.currentPos());
		profileLogLine(msg);
	}

	function profileWarnEvery(kind:String, count:Int, name:String, pos:haxe.macro.Expr.Position, every:Int):Void {
		if (!profileEnabled)
			return;
		profileInit();
		if (every <= 0 || count % every != 0)
			return;
		final now = profileNowS();
		final dt = now - profileStartS;
		final delta = now - profileLastS;
		profileLastS = now;
		final msg = "reflaxe.ocaml: " + kind + " count=" + Std.string(count) + " dt=" + Std.string(Math.round(dt)) + "s (+" + Std.string(Math.round(delta))
			+ "s) last=" + name;
		Context.warning(msg, pos);
		profileLogLine(msg);
	}
	#end

	#if macro
	static var haxeStdRoots:Null<Array<String>> = null;
	static var reflaxeOcamlOwnedRoots:Null<Array<String>> = null;

	static function normalizePath(p:String):String {
		if (p == null)
			return "";
		var s = p.replace("\\", "/");
		if (!s.endsWith("/"))
			s += "/";
		return s;
	}

	static function detectHaxeStdRoots():Array<String> {
		if (haxeStdRoots != null)
			return haxeStdRoots;

		final roots:Array<String> = [];
		for (cp in haxe.macro.Context.getClassPath()) {
			if (cp == null || cp.length == 0)
				continue;

			// Identify the real Haxe std root by probing for known files.
			// Avoid confusing it with this repo's own `std/` folder.
			final stdHx = Path.join([cp, "Std.hx"]);
			final logHx = Path.join([cp, "haxe", "Log.hx"]);
			if (sys.FileSystem.exists(stdHx) && sys.FileSystem.exists(logHx)) {
				roots.push(normalizePath(cp));
			}
		}

		haxeStdRoots = roots;
		return roots;
	}

	static function isPosInHaxeStd(pos:haxe.macro.Expr.Position):Bool {
		final info = haxe.macro.Context.getPosInfos(pos);
		final file = normalizePath(info.file);
		for (root in detectHaxeStdRoots()) {
			if (StringTools.startsWith(file, root))
				return true;
		}
		return false;
	}

	static function detectReflaxeOcamlOwnedRoots():Array<String> {
		if (reflaxeOcamlOwnedRoots != null)
			return reflaxeOcamlOwnedRoots;
		final compilerPath = normalizePath(haxe.macro.Context.resolvePath("reflaxe/ocaml/OcamlCompiler.hx"));
		final suffix = "src/reflaxe/ocaml/OcamlCompiler.hx/";
		if (!StringTools.endsWith(compilerPath, suffix))
			throw 'reflaxe.ocaml [ocaml-representation:package-root]: cannot derive the package root from "$compilerPath"';
		final packageRoot = compilerPath.substr(0, compilerPath.length - suffix.length);
		reflaxeOcamlOwnedRoots = [packageRoot + "src/", packageRoot + "std/"];
		return reflaxeOcamlOwnedRoots;
	}

	/**
		Returns whether a declaration belongs to the target implementation itself.

		The first nominal carrier slice is for application classes. Target
		compiler and target-stdlib classes retain their existing representation
		until a separate runtime-facing contract admits them.
	**/
	static function isPosInReflaxeOcaml(pos:haxe.macro.Expr.Position):Bool {
		final info = haxe.macro.Context.getPosInfos(pos);
		var file = info.file;
		if (!Path.isAbsolute(file))
			file = Path.join([Sys.getCwd(), file]);
		final normalizedFile = normalizePath(file);
		for (root in detectReflaxeOcamlOwnedRoots()) {
			if (StringTools.startsWith(normalizedFile, root))
				return true;
		}
		return false;
	}
	#end

	public function new() {
		super();
		instance = this;

		#if macro
		profileEnabled = Context.defined("reflaxe_ocaml_progress") || Context.defined("reflaxe_ocaml_telemetry");
		profileVerbose = Context.defined("reflaxe_ocaml_telemetry");
		profileClassFilter = Context.definedValue("reflaxe_ocaml_telemetry_class");
		profileFieldFilter = Context.definedValue("reflaxe_ocaml_telemetry_field");
		profileDetail = Context.defined("reflaxe_ocaml_telemetry_detail");
		if (profileEnabled)
			profileInit();
		ctx.profileLogLine = profileEnabled ? ((msg:String) -> profileLogLine(msg)) : null;
		#end
	}

	#if macro
	/** Returns the source-level type name used by module-preparation telemetry. */
	static function profileModuleTypeName(moduleType:ModuleType):String {
		return switch (moduleType) {
			case TClassDecl(reference):
				final type = reference.get();
				(type.pack ?? []).concat([type.name]).join(".");
			case TEnumDecl(reference):
				final type = reference.get();
				(type.pack ?? []).concat([type.name]).join(".");
			case TTypeDecl(reference):
				final type = reference.get();
				(type.pack ?? []).concat([type.name]).join(".");
			case TAbstract(reference):
				final type = reference.get();
				(type.pack ?? []).concat([type.name]).join(".");
		};
	}
	#end

	/**
		Starts target telemetry before Reflaxe extracts and preprocesses fields.

		`compileClassImpl` begins only after the framework has materialized every
		field body for the class. Compiler-scale profiles therefore need this
		earlier boundary to distinguish target rendering from typed-body transfer
		and preprocessing.
	**/
	override public function setupModule(moduleType:Null<ModuleType>):Void {
		#if macro
		if (profileVerbose && moduleType != null) {
			profileModulePrepareStartS = profileNowS();
			profileModulePrepareName = profileModuleTypeName(moduleType);
			profileLogLine("reflaxe.ocaml: module_prepare_begin name=" + profileModulePrepareName);
		} else {
			profileModulePrepareStartS = 0.0;
			profileModulePrepareName = null;
		}
		#end
		super.setupModule(moduleType);
		#if macro
		if (profileVerbose && moduleType != null) {
			final dtMs = Std.int((profileNowS() - profileModulePrepareStartS) * 1000);
			profileLogLine("reflaxe.ocaml: module_setup_end name=" + profileModulePrepareName + " dt_ms=" + Std.string(dtMs));
		}
		#end
	}

	/** Starts a fresh, revision-keyed target-plan registry for this request. */
	override public function beginProgramRevision(revision:ProgramRevision):Void {
		super.beginProgramRevision(revision);
		compilerExpressionOrdinals.clear();
		nextCompilerExpressionOrdinal = 0;
		functionPlanRegistry.beginProgram(revision.id);
		representationRegistry.beginProgram(revision.id);
		staticStoragePlan.beginProgram(revision.id);
		ctx.beginRuntimeRequirementProgram(revision.id);
		#if macro
		try {
			OcamlMonomorphicClassPlanner.plan(pendingStaticStorageModuleOrder, pendingStaticStorageClassesByModule, ctx, representationRegistry,
				classType -> !isPosInHaxeStd(classType.pos) && !isPosInReflaxeOcaml(classType.pos));
			planCallableDeclarations(pendingStaticStorageModuleOrder, pendingStaticStorageClassesByModule, revision.id);
			planMutableStaticStorage(pendingStaticStorageModuleOrder, pendingStaticStorageClassesByModule);
		} catch (error:Dynamic) {
			Context.error(Std.string(error), Context.currentPos());
		}
		#end
	}

	/**
		Builds the first callable declaration catalog from the complete typed program.

		This happens before Reflaxe emits any module, so a caller can be checked
		against the authoritative Haxe declaration even when the callee's final
		body is processed later. The final body still has to publish a matching
		callable boundary before the target command succeeds.
	**/
	function planCallableDeclarations(moduleOrder:Array<String>, moduleToClasses:Map<String, Array<ClassType>>, programRevision:String):Void {
		for (moduleId in moduleOrder) {
			final classes = moduleToClasses.get(moduleId);
			if (classes == null)
				continue;
			for (classType in classes) {
				if (classType.constructor != null) {
					final declaration = OcamlCallPlanner.constructorDeclarationFor(classType, classType.constructor.get(), representationRegistry,
						programRevision, OcamlFunctionPlanRegistry.PIPELINE_REVISION);
					if (declaration != null)
						functionPlanRegistry.registerCallableDeclaration(declaration);
				}
				for (field in classType.statics.get()) {
					final declaration = OcamlCallPlanner.declarationFor(classType, field, true, representationRegistry, programRevision,
						OcamlFunctionPlanRegistry.PIPELINE_REVISION);
					if (declaration != null)
						functionPlanRegistry.registerCallableDeclaration(declaration);
				}
				for (field in classType.fields.get()) {
					final declaration = OcamlCallPlanner.declarationFor(classType, field, false, representationRegistry, programRevision,
						OcamlFunctionPlanRegistry.PIPELINE_REVISION);
					if (declaration != null)
						functionPlanRegistry.registerCallableDeclaration(declaration);
				}
			}
		}
	}

	/** Builds and validates every admitted plan for one final typed function body. */
	public function sealFunctionPlans(data:ClassFuncData):Void {
		new OcamlFunctionPlanSealer(ctx, functionPlanRegistry, representationRegistry, staticStoragePlan).seal(data);
	}

	#if macro
	/**
		Performs request hygiene and validation before Reflaxe fingerprints the program.

		This boundary deliberately avoids whole-program OCaml analysis. Reflaxe first
		reduces the final typed Haxe program and every relevant input to a stable
		identity. An unchanged request can then find a previously validated generated
		OCaml tree before starting the expensive work that the cached result replaces.
	**/
	public override function filterTypes(moduleTypes:Array<haxe.macro.Type.ModuleType>):Array<haxe.macro.Type.ModuleType> {
		OcamlSourcePositionMapper.beginRequest();
		pendingPublishedOutputBuild = null;
		stagedTargetReuseCandidate = null;
		targetReuseRuntimeSourceManifest = null;
		semanticRuntimeAuthority = null;
		nativeSourceDeclarationAuthority = null;
		skippedTargetGenerationWarnings = 0;
		final started = haxe.Timer.stamp();
		targetReuseObservation = captureTargetReuseObservation();
		targetRevisionObservationMilliseconds = elapsedMilliseconds(started);
		targetMissPreparationMilliseconds = 0;
		targetReuseLookupMilliseconds = 0;
		targetReusePayloadValidationMilliseconds = 0;
		targetReplayFilesMilliseconds = 0;
		targetReplayReceiptAndManifestMilliseconds = 0;
		targetReuseLookupRan = false;
		targetMissPreparationRan = false;
		targetReplaySucceeded = false;
		targetReusePayloadBytes = null;
		StrictModeEnforcer.enforceRegisteredTypes(moduleTypes);
		return moduleTypes;
	}

	/**
		Runs whole-program OCaml preparation only when no exact cached result was used.

		This preparation computes representation, call, storage, and runtime decisions
		needed to generate OCaml. An exact cache hit skips it; every edited, uncertain,
		or ineligible request runs it normally.
	**/
	public override function prepareFinalProgram(moduleTypes:Array<ModuleType>, snapshot:FinalProgramFingerprintSnapshot):Void {
		final probe = targetReuseProbe;
		if (probe == null)
			throw "reflaxe.ocaml: miss preparation started before the target reuse probe";
		#if macro
		OcamlTargetReuseTestHooks.failIfExpectedHitReachedMiss();
		if (Context.defined("reflaxe_ocaml_target_reuse_test_require_hit") && probe.requestRevision != null) {
			final unexpectedLease = TargetReuseCatalog.shared().lookup(OcamlTargetReuseContract.NAMESPACE, probe.requestRevision);
			if (unexpectedLease != null) {
				unexpectedLease.close();
				throw "reflaxe.ocaml: exact-hit fixture reached miss-only target preparation despite an exact catalog entry";
			}
		}
		#end
		if (!probe.eligible)
			TargetReuseCatalog.shared().recordIneligible(probe.blockers());
		targetMissPreparationRan = true;
		final started = haxe.Timer.stamp();
		precomputeWholeProgramContext(moduleTypes);
		targetMissPreparationMilliseconds = elapsedMilliseconds(started);
	}

	public override function targetReuseNamespace():Null<String> {
		return OcamlTargetReuseContract.NAMESPACE;
	}

	public override function targetReuseRevisionComponents(snapshot:FinalProgramFingerprintSnapshot):Array<TargetReuseRevisionComponent> {
		return OcamlTargetReuseContract.revisionComponents(requireTargetReuseObservation());
	}

	public override function targetReuseBlockers(snapshot:FinalProgramFingerprintSnapshot):Array<String> {
		return OcamlTargetReuseContract.blockers(requireTargetReuseObservation());
	}

	/**
		Attempts to reuse the complete generated OCaml tree before ordinary generation.

		A reusable entry is an immutable copy of every generated source/build file for
		the exact typed program and configuration. The target validates its identity,
		replays it into a fresh private output transaction, and rebuilds current
		ownership manifests. Invalid bytes or mismatched identity are quarantined and
		become a normal miss. Output or transaction failures remain request failures
		instead of being hidden by a second compilation attempt.
	**/
	public override function tryReplayTargetReuse():Bool {
		#if eval
		final probe = targetReuseProbe;
		final snapshot = finalProgramFingerprint;
		if (probe == null || probe.requestRevision == null || snapshot == null || output == null)
			throw "reflaxe.ocaml: exact replay started without a sealed request or output transaction";
		final requestRevision:String = probe.requestRevision;
		final catalog = TargetReuseCatalog.shared();
		OcamlTargetReuseTestHooks.recordCatalogState("lookup", requestRevision, TargetReuseCatalog.sharedStats());
		targetReuseLookupRan = true;
		final lookupStarted = haxe.Timer.stamp();
		final lease = catalog.lookup(OcamlTargetReuseContract.NAMESPACE, requestRevision);
		targetReuseLookupMilliseconds = elapsedMilliseconds(lookupStarted);
		if (lease == null)
			return false;

		targetReusePayloadBytes = lease.payloadBytes;
		final payload = copyTargetReusePayloadAndClose(lease);
		var candidate:Null<OcamlSourceBundleCandidate> = null;
		final payloadValidationStarted = haxe.Timer.stamp();
		try {
			candidate = OcamlSourceBundleCandidate.decode(payload);
			final normalizedRequestRevision = OcamlArtifactManifestSchema.normalizeRevision(requestRevision, "current target request revision");
			final normalizedProgramRevision = OcamlArtifactManifestSchema.normalizeRevision(snapshot.programRevision.id, "current program revision");
			final normalizedConfigurationRevision = OcamlArtifactManifestSchema.normalizeRevision(requireTargetReuseObservation().sourceConfigurationRevision,
				"current source configuration revision");
			if (candidate.targetRequestRevision != normalizedRequestRevision
				|| candidate.programRevision != normalizedProgramRevision
				|| candidate.configurationRevision != normalizedConfigurationRevision
				|| !candidate.diagnosticsEligible)
				throw "reflaxe.ocaml: exact source bundle does not match the current request";
		} catch (error:Dynamic) {
			targetReusePayloadValidationMilliseconds = elapsedMilliseconds(payloadValidationStarted);
			catalog.quarantine(OcamlTargetReuseContract.NAMESPACE, requestRevision);
			OcamlTargetReuseTestHooks.recordCatalogState("payload-rejected:" + Std.string(error), requestRevision, TargetReuseCatalog.sharedStats());
			catalog.recordMiss("corrupt-payload");
			return false;
		}
		targetReusePayloadValidationMilliseconds = elapsedMilliseconds(payloadValidationStarted);
		OcamlTargetReuseTestHooks.failIfExpectedMissReachedHit();

		try {
			final reusable:OcamlSourceBundleCandidate = cast candidate;
			final replay = OcamlSourceBundleReplay.run(reusable, output);
			targetReplayFilesMilliseconds = replay.fileReplayMilliseconds;
			targetReplayReceiptAndManifestMilliseconds = replay.receiptAndManifestMilliseconds;
			targetReplaySucceeded = true;
			semanticRuntimeAuthority = reusable.semanticRuntimeAuthority;
			nativeSourceDeclarationAuthority = reusable.nativeDependenciesAuthority;
			scheduleReplayBuild(replay.artifacts);
			return true;
		} catch (error:OcamlSourceBundleReplayCorruption) {
			catalog.quarantine(OcamlTargetReuseContract.NAMESPACE, requestRevision);
			catalog.recordMiss("corrupt-replay");
			return false;
		}
		#else
		return false;
		#end
	}

	/**
		Copies one cached source bundle and always releases its catalog lease.

		A lease prevents reset or eviction while bytes are being copied. The returned
		`Bytes` value belongs to this request, so decoding and replay no longer need
		the catalog entry to stay pinned. Closing in both the success and error paths
		prevents a failed allocation or copy from blocking later cache cleanup.
	**/
	static function copyTargetReusePayloadAndClose(lease:reflaxe.lifecycle.TargetReuseCatalog.TargetReuseCatalogLease):Bytes {
		try {
			final payload = lease.copyPayload();
			lease.close();
			return payload;
		} catch (error:Dynamic) {
			lease.close();
			throw error;
		}
	}

	/**
		Makes a newly generated source tree reusable only after the request succeeds.

		The process-local cache receives copied bytes and bounded size accounting, not
		the request's typed Haxe objects, target builders, output writers, or other
		mutable compiler state.
	**/
	public override function finishTargetReuseRequest(outcome:TargetReuseRequestOutcome):Void {
		final candidate = stagedTargetReuseCandidate;
		stagedTargetReuseCandidate = null;
		switch (outcome) {
			case CompiledMiss if (candidate != null):
				final admission = TargetReuseCatalog.shared()
					.admit(OcamlTargetReuseContract.NAMESPACE, candidate.targetRequestRevision, OcamlTargetReuseTestHooks.admissionPayload(candidate),
						OcamlSourceBundleCandidate.ESTIMATED_CATALOG_OVERHEAD_BYTES);
				if (admission.reason == "same-key-different-payload")
					throw "reflaxe.ocaml: one exact target request produced different source-bundle bytes; the reuse namespace was quarantined";
				OcamlTargetReuseTestHooks.recordCatalogState("admission", candidate.targetRequestRevision, TargetReuseCatalog.sharedStats());
			case CompiledMiss | ExactHit | Failed:
		}
		writeTargetReusePhaseReport(outcome, candidate);
		OcamlTargetReuseTestHooks.recordCompactedGcState("request-finish", TargetReuseCatalog.sharedStats());
	}

	function writeTargetReusePhaseReport(outcome:TargetReuseRequestOutcome, candidate:Null<OcamlSourceBundleCandidate>):Void {
		final snapshot = finalProgramFingerprint;
		final probe = targetReuseProbe;
		final realm = targetReuseCatalogRealm;
		final fingerprintAndKeyMilliseconds = finalProgramFingerprintAndKeyMilliseconds;
		final lifecycleMilliseconds = targetReuseLifecycleMilliseconds;
		if (snapshot == null
			|| probe == null
			|| realm == null
			|| fingerprintAndKeyMilliseconds == null
			|| lifecycleMilliseconds == null)
			return;
		final payloadBytes = candidate == null ? targetReusePayloadBytes : candidate.payloadBytes;
		OcamlTargetReusePhaseReportWriter.tryWrite(snapshot, probe, outcome, realm, TargetReuseCatalog.sharedStats(), {
			targetRevisionObservationMilliseconds: targetRevisionObservationMilliseconds,
			finalProgramFingerprintAndKeyMilliseconds: fingerprintAndKeyMilliseconds,
			targetLifecycleMilliseconds: lifecycleMilliseconds,
			missPreparationMilliseconds: targetMissPreparationMilliseconds,
			lookupMilliseconds: targetReuseLookupMilliseconds,
			payloadValidationMilliseconds: targetReusePayloadValidationMilliseconds,
			replayFilesMilliseconds: targetReplayFilesMilliseconds,
			replayReceiptAndManifestMilliseconds: targetReplayReceiptAndManifestMilliseconds,
			outputPublicationMilliseconds: outputPublicationMilliseconds
		}, {
			semanticCompilerRan: targetMissPreparationRan,
			missPreparationRan: targetMissPreparationRan,
			lookupRan: targetReuseLookupRan,
			replaySucceeded: targetReplaySucceeded,
			payloadBytes: payloadBytes
		});
	}

	function requireTargetReuseObservation():OcamlTargetReuseObservation {
		final observation = targetReuseObservation;
		if (observation == null)
			throw "reflaxe.ocaml: target reuse observation was requested before filterTypes";
		return observation;
	}

	function captureTargetReuseObservation():OcamlTargetReuseObservation {
		final outputDirectory = output == null ? null : output.outputDir;
		final outputConfigured = outputDirectory != null && outputDirectory.length > 0;
		final outputProjectName = outputConfigured ? DuneProjectEmitter.defaultProjectName(outputDirectory) : "unconfigured";
		#if macro
		final packageVersion = Context.definedValue("reflaxe.ocaml") ?? "unversioned";
		final sourceConfigurationRevision = OcamlArtifactConfigurationRevision.fromMacroContext(OcamlFunctionPlanRegistry.PIPELINE_REVISION, outputProjectName);
		targetReuseRuntimeSourceManifest = Context.defined("ocaml_no_runtime") ? null : RuntimeCopier.loadCheckedSourceManifest();
		final runtimeInputRevision = targetReuseRuntimeSourceManifest == null ? "sha256:" +
			haxe.crypto.Sha256.encode("runtime-source-input:disabled") : targetReuseRuntimeSourceManifest.revision;
		return {
			packageVersion: packageVersion,
			pipelineRevision: OcamlFunctionPlanRegistry.PIPELINE_REVISION,
			sourceConfigurationRevision: sourceConfigurationRevision,
			outputSchemaRevision: '${OcamlArtifactManifestSchema.MODEL}:v${OcamlArtifactManifestSchema.SCHEMA_VERSION}:framework-receipt-v1',
			runtimeInputRevision: runtimeInputRevision,
			nativeSourceInputRevision: OcamlSourceBundleAuthority.nativeInputRevision(sourceConfigurationRevision),
			targetImplementationRevision: OcamlTargetImplementationRevision.current(),
			reuseEnabled: Context.defined("reflaxe_ocaml_target_reuse"),
			transactionalOutputEnabled: Context.defined("reflaxe_output_transaction"),
			mliEnabled: Context.defined("ocaml_mli"),
			outputConfigured: outputConfigured,
			progressOrTelemetryEnabled: profileEnabled,
			loweringReportEnabled: Context.defined("ocaml_lowering_report"),
			lifecycleTraceEnabled: Context.defined("reflaxe_ocaml_semantic_lifecycle_trace")
		};
		#else
		return {
			packageVersion: "runtime-unversioned",
			pipelineRevision: OcamlFunctionPlanRegistry.PIPELINE_REVISION,
			sourceConfigurationRevision: OcamlArtifactConfigurationRevision.fromValues(OcamlFunctionPlanRegistry.PIPELINE_REVISION, outputProjectName, []),
			outputSchemaRevision: '${OcamlArtifactManifestSchema.MODEL}:v${OcamlArtifactManifestSchema.SCHEMA_VERSION}:framework-receipt-v1',
			runtimeInputRevision: "sha256:" + haxe.crypto.Sha256.encode("runtime-source-input:runtime-unavailable"),
			nativeSourceInputRevision: OcamlSourceBundleAuthority.nativeInputRevision(OcamlArtifactConfigurationRevision.fromValues(OcamlFunctionPlanRegistry.PIPELINE_REVISION,
				outputProjectName, [])),
			targetImplementationRevision: null,
			reuseEnabled: false,
			transactionalOutputEnabled: false,
			mliEnabled: false,
			outputConfigured: outputConfigured,
			progressOrTelemetryEnabled: false,
			loweringReportEnabled: false,
			lifecycleTraceEnabled: false
		};
		#end
	}

	static function elapsedMilliseconds(started:Float):Int {
		return Std.int(Math.max(0, (haxe.Timer.stamp() - started) * 1000));
	}

	function precomputeWholeProgramContext(types:Array<haxe.macro.Type.ModuleType>):Void {
		if (ctx.virtualTypesComputed)
			return;
		ctx.virtualTypesComputed = true;

		if (profileEnabled) {
			profileInit();
			final now = profileNowS();
			final msg = "reflaxe.ocaml: after typing moduleTypes="
				+ Std.string(types.length)
				+ " dt="
				+ Std.string(Math.round(now - profileStartS))
				+ "s";
			Context.warning(msg, Context.currentPos());
			profileLogLine(msg);
		}

		// Primary-type mapping (naming): keep historical short names stable when a module
		// only contains a single type, even if that type name differs from the file/module name.
		final moduleToClasses:Map<String, Array<ClassType>> = [];
		final moduleOrder:Array<String> = [];

		inline function fullNameOf(c:ClassType):String {
			return (c.pack ?? []).concat([c.name]).join(".");
		}

		function markChain(c:ClassType):Void {
			var cur:Null<ClassType> = c;
			var guard = 0;
			while (cur != null && guard++ < 64) {
				ctx.virtualTypes.set(fullNameOf(cur), true);
				ctx.dispatchTypes.set(fullNameOf(cur), true);
				cur = cur.superClass != null ? cur.superClass.t.get() : null;
			}
		}

		for (t in types) {
			switch (t) {
				case TClassDecl(cRef):
					final c = cRef.get();

					if (!moduleToClasses.exists(c.module)) {
						moduleToClasses.set(c.module, []);
						moduleOrder.push(c.module);
					}
					final list = moduleToClasses.get(c.module);
					if (list != null)
						list.push(c);

					if (c.isInterface) {
						ctx.interfaceTypes.set(fullNameOf(c), true);
					}
					if (c.interfaces != null && c.interfaces.length > 0 && !c.isInterface) {
						ctx.dispatchTypes.set(fullNameOf(c), true);
					}
					if (c.superClass != null) {
						markChain(c);
					}
				case _:
			}
		}

		for (moduleId => list in moduleToClasses) {
			if (list == null || list.length == 0)
				continue;
			final base = OcamlNameTools.moduleBaseName(moduleId);
			var primary:Null<String> = null;
			for (c in list) {
				if (c.name == base) {
					primary = c.name;
					break;
				}
			}
			if (primary == null)
				primary = list[0].name;
			if (primary != null)
				ctx.primaryTypeNameByModule.set(moduleId, primary);
		}

		// Reserve every Haxe class binding that can become a module-level OCaml
		// value. Generic Haxe/Reflaxe rewrites may introduce locals named `index`,
		// `create`, or another member name; target local allocation must keep those
		// temporaries from hiding later calls in the same OCaml module.
		for (t in types) {
			switch (t) {
				case TClassDecl(cRef):
					final c = cRef.get();
					final fullName = fullNameOf(c);
					ctx.reserveModuleValueName(c.module, "__reflaxe_ocaml__");
					if (!c.isInterface && !c.isExtern) {
						ctx.reserveModuleValueName(c.module, ctx.scopedValueName(c.module, c.name, "create"));
						ctx.reserveModuleValueName(c.module, ctx.scopedValueName(c.module, c.name, "__empty"));
						ctx.reserveModuleValueName(c.module, ctx.scopedValueName(c.module, c.name, "__ctor"));
					}
					final usesDispatch = !c.isInterface && ctx.dispatchTypes.exists(fullName);
					for (field in c.fields.get()) {
						switch (field.kind) {
							case FMethod(_) if (field.name != "new"):
								final memberName = usesDispatch ? field.name + "__impl" : field.name;
								ctx.reserveModuleValueName(c.module, ctx.scopedValueName(c.module, c.name, memberName));
							case _:
						}
					}
					for (field in c.statics.get()) {
						switch (field.kind) {
							case FMethod(_) | FVar(_, _):
								ctx.reserveModuleValueName(c.module, ctx.scopedValueName(c.module, c.name, field.name));
						}
					}
				case _:
			}
		}

		pendingStaticStorageModuleOrder = moduleOrder.copy();
		pendingStaticStorageClassesByModule = moduleToClasses;
	}

	/**
		Inventories mutable static cells while the complete typed program is available.

		Exact `Int` cells may be declared at the start of a module because their
		carrier is independently proven not to depend on generated class types. Other
		cells are declared immediately after the last generated class type required by
		their carrier, when that still precedes their owner initialization. A cell stays
		with its owner when no earlier type-safe declaration point exists.
	**/
	function planMutableStaticStorage(moduleOrder:Array<String>, moduleToClasses:Map<String, Array<ClassType>>):Void {
		function initializerDependencyKeys(initializer:Null<TypedExpr>):Array<String> {
			if (initializer == null)
				return [];
			final dependencies:Map<String, Bool> = [];
			function scan(expression:TypedExpr):Void {
				switch (expression.expr) {
					case TFunction(_):
						return;
					case TField(_, FStatic(classReference, fieldReference)):
						final dependencyClass = classReference.get();
						final dependencyField = fieldReference.get();
						final isMutableStorage = switch (dependencyField.kind) {
							case FVar(_, _): !dependencyField.isFinal;
							case FMethod(MethDynamic): true;
							case _: false;
						};
						if (isMutableStorage)
							dependencies.set(OcamlStaticStoragePlan.key(dependencyClass.module, dependencyClass.name, dependencyField.name), true);
					case _:
				}
				haxe.macro.TypedExprTools.iter(expression, scan);
			}
			scan(initializer);
			final out = [for (key in dependencies.keys()) key];
			out.sort(Reflect.compare);
			return out;
		}

		for (moduleId in moduleOrder) {
			final classes = moduleToClasses.get(moduleId);
			if (classes == null)
				continue;
			final concrete = classes.filter(classType -> !classType.isExtern && !classType.isInterface);
			final primary = ctx.primaryTypeNameByModule.get(moduleId);
			final ordered = [for (index in 0...concrete.length) {classType: concrete[index], index: index}];
			ordered.sort((left, right) -> {
				final leftPrimary = left.classType.name == primary ? 1 : 0;
				final rightPrimary = right.classType.name == primary ? 1 : 0;
				if (leftPrimary != rightPrimary)
					return leftPrimary - rightPrimary;
				return left.index - right.index;
			});
			final targetTypeOrderByName:Map<String, Int> = [];
			for (typeOrder in 0...ordered.length) {
				final orderedType = ordered[typeOrder].classType;
				targetTypeOrderByName.set(ctx.scopedInstanceTypeName(moduleId, orderedType.name), typeOrder);
			}

			function latestCarrierTypeOrder(type:OcamlTypeExpr):Int {
				return switch (type) {
					case TIdent(name):
						final selected = targetTypeOrderByName.get(name);
						selected == null ? -1 : selected;
					case TApp(name, parameters):
						var latest = targetTypeOrderByName.exists(name) ? targetTypeOrderByName.get(name) : -1;
						for (parameter in parameters)
							latest = Std.int(Math.max(latest, latestCarrierTypeOrder(parameter)));
						latest;
					case TArrow(from, to): Std.int(Math.max(latestCarrierTypeOrder(from), latestCarrierTypeOrder(to)));
					case TTuple(items):
						var latest = -1;
						for (item in items)
							latest = Std.int(Math.max(latest, latestCarrierTypeOrder(item)));
						latest;
					case TVar(_): -1;
					case TRecord(fields):
						var latest = -1;
						for (field in fields)
							latest = Std.int(Math.max(latest, latestCarrierTypeOrder(field.typ)));
						latest;
				}
			}

			var order = 0;
			for (typeOrder in 0...ordered.length) {
				final orderedClass = ordered[typeOrder];
				final classType = orderedClass.classType;
				staticStoragePlan.registerTypeOrder(moduleId, classType.name, typeOrder);
				final fields = classType.statics.get();
				final orderedFields = fields.filter(field -> switch (field.kind) {
					case FMethod(MethDynamic): true;
					case _: false;
				}).concat(fields.filter(field -> switch (field.kind) {
					case FVar(_, _): !field.isFinal;
					case _: false;
				}));
				for (field in orderedFields) {
					final kind = switch (field.kind) {
						case FMethod(MethDynamic): OcamlStaticStorageKind.DynamicMethod;
						case FVar(_, _): OcamlStaticStorageKind.Variable;
						case _: continue;
					}
					final representation = kind == OcamlStaticStorageKind.Variable ? selectRepresentedField(field.type,
						OcamlRepresentationDomain.StaticField) : null;
					final representedField = representation == null ? null : OcamlFieldRepresentationMaterializer.materializeRepresentedField(representation,
						OcamlRepresentationDomain.StaticField);
					final previousModuleId = ctx.currentModuleId;
					final previousTypeName = ctx.currentTypeName;
					ctx.currentModuleId = moduleId;
					ctx.currentTypeName = classType.name;
					final carrierType = representedField == null ? ocamlTypeExprFromHaxeType(field.type) : representedField.carrierType;
					ctx.currentModuleId = previousModuleId;
					ctx.currentTypeName = previousTypeName;
					final useModulePrelude = representedField != null && concrete.length > 1;
					final latestCarrierDependency = latestCarrierTypeOrder(carrierType);
					if (!useModulePrelude && latestCarrierDependency > typeOrder) {
						final dependencyTypeName = ordered[latestCarrierDependency].classType.name;
						throw 'reflaxe.ocaml [ocaml-static-storage:representation-order-incompatible]: mutable static "$moduleId::${classType.name}::${field.name}" uses OCaml carrier "${printer.printType(carrierType)}", which depends on later type "$dependencyTypeName"; its storage cannot be declared before use without changing Haxe initialization order';
					}
					final useTypePrelude = !useModulePrelude && concrete.length > 1 && latestCarrierDependency <= typeOrder;
					final declarationTypeOrder = useTypePrelude ? Std.int(Math.max(0, latestCarrierDependency)) : -1;
					final declarationTypeName = useTypePrelude ? ordered[declarationTypeOrder].classType.name : null;
					staticStoragePlan.register({
						moduleId: moduleId,
						ownerTypeName: classType.name,
						fieldName: field.name,
						targetValueName: ctx.scopedValueName(moduleId, classType.name, field.name),
						semanticTypeId: representation == null ? TypeTools.toString(field.type) : representation.semanticTypeId,
						carrierTypeId: representation != null ? representation.carrierTypeId : printer.printType(carrierType),
						fieldType: field.type,
						carrierType: carrierType,
						kind: kind,
						declarationSite: useModulePrelude ? OcamlStaticStorageDeclarationSite.ModulePrelude : (useTypePrelude ? OcamlStaticStorageDeclarationSite.TypePrelude : OcamlStaticStorageDeclarationSite.OwnerBinding),
						declarationTypeName: declarationTypeName,
						declarationTypeOrder: declarationTypeOrder,
						ownerTypeOrder: typeOrder,
						declarationOrder: order,
						initializationOrder: order,
						hasInitializer: field.expr() != null,
						initializerDependencyKeys: initializerDependencyKeys(field.expr()),
						representationId: representation == null ? null : representation.id
					});
					order += 1;
				}
			}
		}
		staticStoragePlan.seal();
	}
	#end

	/** Emits only cells whose proven carrier may safely precede generated class types. */
	function staticStoragePrelude(moduleId:String, emittedOwnerTypes:Map<String, Bool>):String {
		final items:Array<OcamlModuleItem> = [];
		for (entry in staticStoragePlan.entriesForModule(moduleId)) {
			if (entry.declarationSite != OcamlStaticStorageDeclarationSite.ModulePrelude || !emittedOwnerTypes.exists(entry.ownerTypeName))
				continue;
			if (entry.representationId == null)
				staticStorageInvariant('module-prelude cell "${entry.key}" has no representation decision');
			final representedField = requireStaticFieldRepresentation(entry);
			if (representedField == null)
				staticStorageInvariant('module-prelude cell "${entry.key}" did not resolve its exact field representation');
			final initialValue = OcamlExpr.EAnnot(representedField.implicitDefault, representedField.carrierType);
			items.push(OcamlModuleItem.ILet([
				{
					name: entry.targetValueName,
					expr: OcamlExpr.EApp(OcamlExpr.EIdent("ref"), [initialValue])
				}
			], false));
		}
		RuntimeUsageCollector.collectFromModuleItems(items, moduleName -> ctx.markRuntimeModule(moduleName));
		return printer.printModule(items);
	}

	public override function generateOutputIterator():Iterator<DataAndFileInfo<reflaxe.output.StringOrBytes>> {
		// Ensure type declarations (enums/typedefs/abstracts) appear before value
		// definitions in each module, since OCaml requires constructors/types to
		// be declared before use.
		//
		// Also ensure that for Haxe modules containing multiple types (e.g. `Main.hx` defines
		// both `Main` and `MyExn`), we emit non-primary types first. Otherwise the primary
		// type's compiled chunk can refer to helper values that appear later in the file,
		// which OCaml does not allow (no forward references for values).
		final sortedClasses:CompiledCollection<String> = {
			final withIndex:Array<{item:DataAndFileInfo<String>, idx:Int}> = [];
			for (i in 0...classes.length)
				withIndex.push({item: classes[i], idx: i});

			final moduleOrder:Map<String, Int> = [];
			var nextMod = 0;
			for (entry in withIndex) {
				final m = entry.item.baseType.module;
				if (!moduleOrder.exists(m))
					moduleOrder.set(m, nextMod++);
			}

			inline function isPrimary(entry:{item:DataAndFileInfo<String>, idx:Int}):Bool {
				final moduleId = entry.item.baseType.module;
				final primary = ctx.primaryTypeNameByModule.get(moduleId);
				if (primary != null)
					return entry.item.baseType.name == primary;
				return OcamlNameTools.isPrimaryTypeInModule(moduleId, entry.item.baseType.name);
			}

			withIndex.sort((a, b) -> {
				final modA = a.item.baseType.module;
				final modB = b.item.baseType.module;
				final ordA = moduleOrder.get(modA);
				final ordB = moduleOrder.get(modB);
				if (ordA != ordB)
					return ordA - ordB;

				final priA = isPrimary(a) ? 1 : 0;
				final priB = isPrimary(b) ? 1 : 0;
				if (priA != priB)
					return priA - priB;

				return a.idx - b.idx;
			});

			withIndex.map(e -> e.item);
		};

		final all:CompiledCollection<String> = enums.concat(typedefs).concat(abstracts).concat(sortedClasses);

		#if macro
		if (!checkedOutputCollisions) {
			checkedOutputCollisions = true;
			assertNoModuleNameCollisions(all);
		}
		#end

		// Improve OCaml error messages by ensuring the compiler reports locations using the
		// stable, user-facing file path in the output directory rather than dune's `_build/` paths.
		//
		// We do this by:
		// - grouping all type-chunks per output file here (instead of letting Reflaxe join them),
		// - then prefixing the combined module with an OCaml line directive:
		//     # 1 "MyModule.ml"
		//
		// This keeps line numbers stable and makes errors actionable without hunting
		// through dune artifacts. Disable with `-D ocaml_no_line_directives`.
		final useLineDirectives = #if macro !Context.defined("ocaml_no_line_directives") #else false #end;
		final ext = options.fileOutputExtension != null ? options.fileOutputExtension : "";

		final buckets:Map<String, {rep:DataAndFileInfo<String>, parts:Array<String>, ownerTypeNames:Map<String, Bool>}> = [];
		final fileOrder:Array<String> = [];

		inline function outputKey(info:DataAndFileInfo<String>):String {
			final base = info.baseType.moduleId();
			return (info.overrideDirectory != null ? info.overrideDirectory + "/" : "") + (info.overrideFileName != null ? info.overrideFileName : base);
		}

		for (info in all) {
			final key = outputKey(info);
			if (!buckets.exists(key)) {
				buckets.set(key, {rep: info, parts: [], ownerTypeNames: []});
				fileOrder.push(key);
			}
			final b = buckets.get(key);
			if (b != null) {
				b.parts.push(info.data);
				b.ownerTypeNames.set(info.baseType.name, true);
			}
		}

		var index = 0;
		return {
			hasNext: () -> index < fileOrder.length,
			next: () -> {
				final key = fileOrder[index++];
				final bucket = buckets.get(key);
				if (bucket == null)
					throw "Missing output bucket for: " + key;
				final staticPrelude = staticStoragePrelude(bucket.rep.baseType.module, bucket.ownerTypeNames);
				final joined = (staticPrelude.length == 0 ? [] : [staticPrelude]).concat(bucket.parts).join("\n\n");

				final out = if (!useLineDirectives || joined.length == 0) {
					joined;
				} else {
					final fileName = key + ext;
					"# 1 \"" + escapeOcamlString(fileName) + "\"\n" + joined;
				}

				return bucket.rep.withOutput(out);
			}
		};
	}

	#if macro
	static function isValidOcamlModuleName(name:String):Bool {
		if (name == null || name.length == 0)
			return false;
		final first = name.charCodeAt(0);
		final isUpper = first >= 65 && first <= 90;
		if (!isUpper)
			return false;
		for (i in 1...name.length) {
			final c = name.charCodeAt(i);
			final ok = (c >= 97 && c <= 122) // a-z
				|| (c >= 65 && c <= 90) // A-Z
				|| (c >= 48 && c <= 57) // 0-9
				|| c == 95; // _
			if (!ok)
				return false;
		}
		return true;
	}

	function assertNoModuleNameCollisions(all:CompiledCollection<String>):Void {
		// Reflaxe writes output per module using `BaseTypeHelper.moduleId()` as the filename key.
		// That operation replaces '.' with '_' and keeps original case.
		//
		// We must detect collisions early because:
		// - `a.b.C` and `a_b.C` both become `a_b_C` (silent merge into one .ml file).
		// - `foo.Bar` and `Foo.Bar` become `foo_Bar` / `Foo_Bar`, which can collide on
		//   case-insensitive filesystems and/or map to the same OCaml module name.
		final fileKeyToModules:Map<String, Map<String, Bool>> = [];
		final fileKeyToFileIds:Map<String, Map<String, Bool>> = [];

		final ocamlNameToModules:Map<String, Map<String, Bool>> = [];
		final ocamlNameToFileIds:Map<String, Map<String, Bool>> = [];

		inline function addToSet(map:Map<String, Map<String, Bool>>, key:String, value:String):Void {
			if (!map.exists(key))
				map.set(key, []);
			final s = map.get(key);
			if (s != null)
				s.set(value, true);
		}

		for (c in all) {
			final mod = c.baseType.module;
			final fileId = ctx.fileIdForModuleId(mod);

			final fileKey = fileId.toLowerCase();
			addToSet(fileKeyToModules, fileKey, mod);
			addToSet(fileKeyToFileIds, fileKey, fileId);

			final ocamlName = ctx.ocamlModuleNameForModuleId(mod);
			addToSet(ocamlNameToModules, ocamlName, mod);
			addToSet(ocamlNameToFileIds, ocamlName, fileId);

			if (!isValidOcamlModuleName(ocamlName)) {
				Context.error("reflaxe.ocaml (M8): invalid OCaml module name '" + ocamlName + "' derived from Haxe module '" + mod + "'.",
					Context.currentPos());
			}
		}

		for (k => mods in fileKeyToModules) {
			if (mods == null)
				continue;
			var count = 0;
			final modList:Array<String> = [];
			for (m => _ in mods) {
				count += 1;
				modList.push(m);
			}
			if (count <= 1)
				continue;

			final fileIds = fileKeyToFileIds.get(k);
			final fileIdList:Array<String> = [];
			if (fileIds != null)
				for (f => _ in fileIds)
					fileIdList.push(f);
			modList.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
			fileIdList.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));

			Context.error("reflaxe.ocaml (M8): module filename collision after flattening.\n"
				+ "The following Haxe modules would map to the same output file key '"
				+ k
				+ "':\n"
				+ "  - "
				+ modList.join("\n  - ")
				+ "\n"
				+ (fileIdList.length > 0 ? ("File ids involved: " + fileIdList.join(", ") + "\n") : "")
				+ "Rename one of the packages/modules to avoid '.'/'_' collisions.\n"
				+ "(bd: haxe.ocaml-28t.9.7)",
				Context.currentPos());
		}

		for (ocamlName => mods in ocamlNameToModules) {
			if (mods == null)
				continue;
			var count = 0;
			final modList:Array<String> = [];
			for (m => _ in mods) {
				count += 1;
				modList.push(m);
			}
			if (count <= 1)
				continue;

			final fileIds = ocamlNameToFileIds.get(ocamlName);
			final fileIdList:Array<String> = [];
			if (fileIds != null)
				for (f => _ in fileIds)
					fileIdList.push(f);
			modList.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
			fileIdList.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));

			// This can happen even if the raw `fileId` differs only by case. OCaml's module name is
			// derived from the filename and starts uppercase, so two files can still define the same module.
			Context.error("reflaxe.ocaml (M8): OCaml module name collision ('"
				+ ocamlName
				+ "').\n"
				+ "The following Haxe modules would define the same OCaml module:\n"
				+ "  - "
				+ modList.join("\n  - ")
				+ "\n"
				+ (fileIdList.length > 0 ? ("File ids involved: " + fileIdList.join(", ") + "\n") : "")
				+ "(bd: haxe.ocaml-28t.9.7)",
				Context.currentPos());
		}
	}
	#end

	function hasStaticMainMethod(funcFields:Array<ClassFuncData>):Bool {
		for (funcField in funcFields) {
			if (funcField.isStatic && funcField.field.name == "main")
				return true;
		}
		return false;
	}

	function recordStaticMainCandidate(moduleId:String, moduleFileId:String, className:String):Void {
		if (staticMainCandidateFileIdByModule.exists(moduleId))
			return;
		staticMainCandidateModules.push(moduleId);
		staticMainCandidateFileIdByModule.set(moduleId, moduleFileId);
		staticMainCandidateClassNameByModule.set(moduleId, className);
	}

	function resolveMainModuleFromMainExpr():Null<String> {
		final mainModule = getMainModule();
		return switch (mainModule) {
			case TClassDecl(classRef):
				final classType = classRef.get();
				ctx.fileIdForModuleId(classType.module);
			case _:
				null;
		}
	}

	function inferMainModuleIdFromStaticMainCandidates():Null<String> {
		if (staticMainCandidateModules.length == 0)
			return null;
		if (staticMainCandidateModules.length == 1) {
			final moduleId = staticMainCandidateModules[0];
			return staticMainCandidateFileIdByModule.get(moduleId);
		}
		for (moduleId in staticMainCandidateModules) {
			final className = staticMainCandidateClassNameByModule.get(moduleId);
			if (className == "Main") {
				return staticMainCandidateFileIdByModule.get(moduleId);
			}
		}
		#if macro
		skippedTargetGenerationWarnings += 1;
		Context.warning("reflaxe.ocaml: unable to infer a unique entrypoint module from static main candidates; set"
			+ " -D ocaml_dune_exes=<exe>:<module> to disambiguate.",
			Context.currentPos());
		#end
		return null;
	}

	function resolveMainModuleIdForDune():Null<String> {
		if (mainModuleId != null)
			return mainModuleId;

		final fromMainExpr = resolveMainModuleFromMainExpr();
		if (fromMainExpr != null) {
			mainModuleId = fromMainExpr;
			return fromMainExpr;
		}

		final fromStaticMainCandidates = inferMainModuleIdFromStaticMainCandidates();
		if (fromStaticMainCandidates != null) {
			mainModuleId = fromStaticMainCandidates;
			return fromStaticMainCandidates;
		}
		return null;
	}

	function staticStorageInvariant(message:String):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-static-storage:invariant]: " + message;
		#if macro
		Context.error(diagnostic, Context.currentPos());
		#end
		throw diagnostic;
	}

	function requireStaticStorage(classType:ClassType, field:ClassField, expectedKind:OcamlStaticStorageKind):OcamlStaticStorageEntry {
		final entry = try {
			staticStoragePlan.require(classType.module, classType.name, field.name);
		} catch (error:Dynamic) {
			return staticStorageInvariant(Std.string(error));
		}
		if (entry.kind != expectedKind)
			return staticStorageInvariant('"${entry.key}" was planned as ${entry.kind}, but type emission requires $expectedKind');
		final representedField = requireStaticFieldRepresentation(entry);
		final actualCarrier = printer.printType(representedField == null ? ocamlTypeExprFromHaxeType(field.type) : representedField.carrierType);
		if (entry.carrierTypeId != actualCarrier)
			return staticStorageInvariant('"${entry.key}" was planned with carrier ${entry.carrierTypeId}, but type emission selected $actualCarrier');
		return entry;
	}

	/** Resolves one sealed represented static field without consulting the legacy type mapper. */
	function requireStaticFieldRepresentation(entry:OcamlStaticStorageEntry):Null<OcamlFieldRepresentationMaterialization> {
		if (entry.representationId == null)
			return null;
		final decision = try {
			representationRegistry.require(entry.representationId, entry.programRevision);
		} catch (error:Dynamic) {
			return staticStorageInvariant(Std.string(error));
		}
		if (decision.semanticTypeId != entry.semanticTypeId || decision.carrierTypeId != entry.carrierTypeId) {
			return
				staticStorageInvariant('"${entry.key}" expects ${entry.semanticTypeId} on ${entry.carrierTypeId}, but ${decision.id} selects ${decision.semanticTypeId} on ${decision.carrierTypeId}');
		}
		return try {
			OcamlFieldRepresentationMaterializer.materializeRepresentedField(decision, OcamlRepresentationDomain.StaticField);
		} catch (error:Dynamic) {
			staticStorageInvariant(Std.string(error));
		}
	}

	/** Selects one explicitly admitted field representation, when applicable. */
	function selectRepresentedField(type:Type, domain:OcamlRepresentationDomain):Null<OcamlRepresentationDecision> {
		if (OcamlRepresentationRegistry.isExactInt(type))
			return representationRegistry.selectExactInt(domain);
		if (OcamlRepresentationRegistry.isExactBool(type))
			return representationRegistry.selectExactBool(domain);
		if (OcamlRepresentationRegistry.isExactNullInt(type))
			return representationRegistry.selectExactNullInt(domain);
		if (OcamlRepresentationRegistry.isExactNullBool(type))
			return representationRegistry.selectExactNullBool(domain);
		if (OcamlRepresentationRegistry.isExactString(type))
			return representationRegistry.selectExactString(domain);
		return null;
	}

	/** Materializes one admitted instance field, when applicable. */
	function representedInstanceField(type:Type):Null<OcamlFieldRepresentationMaterialization> {
		final decision = selectRepresentedField(type, OcamlRepresentationDomain.InstanceField);
		return decision == null ? null : OcamlFieldRepresentationMaterializer.materializeRepresentedField(decision, OcamlRepresentationDomain.InstanceField);
	}

	/** Returns one instance field's selected carrier or the explicitly unmigrated mapper. */
	function instanceFieldCarrier(type:Type):OcamlTypeExpr {
		final represented = representedInstanceField(type);
		return represented == null ? ocamlTypeExprFromHaxeType(type) : represented.carrierType;
	}

	/** Validates an admitted class record against its sealed nominal layout. */
	function validateMonomorphicClassLayout(classType:ClassType, instanceTypeName:String, typeFields:Array<OcamlTypeRecordField>):Void {
		final semanticTypeId = (classType.pack ?? []).concat([classType.name]).join(".");
		final decision = representationRegistry.monomorphicClass(semanticTypeId);
		if (decision == null)
			return;
		final targetModuleName = ctx.ocamlModuleNameForModuleId(classType.module);
		if (decision.sourceModuleId != classType.module
			|| decision.sourceTypeName != classType.name
			|| decision.targetModuleName != targetModuleName
			|| decision.targetTypeName != instanceTypeName
			|| decision.canonicalCarrierTypeId != targetModuleName + "." + instanceTypeName) {
			throw 'reflaxe.ocaml [ocaml-representation:class-layout-owner-mismatch]: $semanticTypeId no longer matches sealed layout ${decision.id}';
		}
		if (typeFields.length != decision.fields.length + 1
			|| typeFields[0].name != "__hx_type"
			|| printer.printType(typeFields[0].typ) != "Obj.t")
			throw 'reflaxe.ocaml [ocaml-representation:class-layout-shape-mismatch]: $semanticTypeId no longer has the sealed runtime-header and field count';
		for (index in 0...decision.fields.length) {
			final planned = decision.fields[index];
			final emitted = typeFields[index + 1];
			final actualCarrier = printer.printType(emitted.typ);
			if (planned.declarationOrder != index
				|| planned.targetFieldName != emitted.name
				|| planned.carrierTypeId != actualCarrier
				|| !emitted.isMutable) {
				throw 'reflaxe.ocaml [ocaml-representation:class-layout-field-mismatch]: $semanticTypeId field $index expected ${planned.targetFieldName}:${planned.carrierTypeId}, but emission selected ${emitted.name}:$actualCarrier';
			}
			final fieldRepresentation = representationRegistry.require(planned.representationId, decision.programRevision);
			if (fieldRepresentation.semanticTypeId != planned.semanticTypeId
				|| fieldRepresentation.carrierTypeId != planned.carrierTypeId
				|| fieldRepresentation.domain != OcamlRepresentationDomain.InstanceField) {
				throw 'reflaxe.ocaml [ocaml-representation:class-layout-field-representation-mismatch]: $semanticTypeId.${planned.sourceFieldName} no longer matches ${planned.representationId}';
			}
		}
	}

	/** Returns one instance field's selected implicit default or the unmigrated default mapper. */
	function instanceFieldDefault(type:Type):OcamlExpr {
		final represented = representedInstanceField(type);
		return represented == null ? defaultValueForType(type) : represented.implicitDefault;
	}

	/** Reports whether a typed initializer is the canonical Haxe null literal. */
	static function isLiteralNullInitializer(initializer:Null<TypedExpr>):Bool {
		if (initializer == null)
			return false;
		return switch (initializer.expr) {
			case TConst(TNull): true;
			case _: false;
		}
	}

	/** Returns one stable owner for a typed class-field initializer. */
	static function fieldInitializerOwner(classType:ClassType, field:ClassField, kind:String):String {
		return 'field-initializer:$kind:${classType.module}|${classType.name}::${field.name}';
	}

	/**
		Returns one request-local owner for an expression compiled outside a field or function.

		Reflaxe can ask the target to compile two distinct macro-generated roots
		that carry the same source span and the same expression structure. The
		zero-based ordinal distinguishes those typed objects, while a repeated call
		for the same object receives the same owner. The map is cleared when the
		next complete program begins and is never part of a reusable cache entry.
	**/
	function compilerExpressionOwner(expression:TypedExpr):String {
		var ordinal = compilerExpressionOrdinals.get(expression);
		if (ordinal == null) {
			ordinal = nextCompilerExpressionOrdinal++;
			compilerExpressionOrdinals.set(expression, ordinal);
		}
		final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
		return 'compiler-expression:${source.file}:${source.min}:${source.max}:root:$ordinal';
	}

	/**
		Seals occurrence-bound plans for one non-function typed root.

		Class-field initializers do not belong to a function, but container
		conversions, anonymous-object operations, and Bytes operations inside them
		still need the same exact program, body, target-pipeline, and runtime
		requirement evidence before syntax is built.
	**/
	function sealStandaloneExpression(ownerId:String, expression:TypedExpr):OcamlSealedStandaloneExpressionPlan {
		final plan = functionPlanRegistry.sealStandaloneExpression(ownerId, expression, representationRegistry);
		for (conversion in plan.containerElements.decisions())
			ctx.recordEnumDynamicContainerRuntimeRequirement(conversion);
		for (decision in plan.anonymousStructures.operations())
			ctx.recordAnonymousStructureRuntimeRequirement(decision);
		for (decision in plan.structuralFields.decisions())
			ctx.recordStructuralFieldRuntimeRequirement(decision);
		for (decision in plan.bytesAccesses.decisions())
			ctx.recordBytesAccessRuntimeRequirements(decision);
		for (decision in plan.bytesMutations.decisions())
			ctx.recordBytesMutationRuntimeRequirements(decision);
		for (decision in plan.bytesProducers.decisions())
			ctx.recordBytesProducerRuntimeRequirements(decision);
		for (decision in plan.bytesReads.decisions())
			ctx.recordBytesReadRuntimeRequirements(decision);
		return plan;
	}

	/** Builds a non-function root after selecting its exact typed plans. */
	function buildStandaloneExpression(builder:OcamlBuilder, ownerId:String, expression:TypedExpr):OcamlExpr {
		final localIdentities = LexicalLocalIdentityPlan.build("standalone:" + ownerId, expression);
		return builder.buildStandaloneExpr(expression, localIdentities, OcamlLocalStoragePlanner.planExpression(expression, localIdentities),
			sealStandaloneExpression(ownerId, expression));
	}

	/** Builds a field initializer with its assignment and Bytes decisions sealed. */
	function buildStandaloneAssignment(builder:OcamlBuilder, ownerId:String, fieldType:Type, expression:TypedExpr):OcamlExpr {
		final localIdentities = LexicalLocalIdentityPlan.build("standalone:" + ownerId, expression);
		return builder.buildStandaloneExprForAssignment(fieldType, expression, localIdentities,
			OcamlLocalStoragePlanner.planExpression(expression, localIdentities), sealStandaloneExpression(ownerId, expression));
	}

	public function compileClassImpl(classType:ClassType, varFields:Array<ClassVarData>, funcFields:Array<ClassFuncData>):Null<String> {
		#if macro
		final profClassStartS = profileEnabled ? profileNowS() : 0.0;
		final profClassName = (classType.pack ?? []).concat([classType.name]).join(".");
		final profClassOrdinal = profClassCount + 1;
		if (profileVerbose && profileModulePrepareStartS > 0.0 && profileModulePrepareName == profClassName) {
			final dtMs = Std.int((profClassStartS - profileModulePrepareStartS) * 1000);
			profileLogLine("reflaxe.ocaml: class_prepare_end count="
				+ Std.string(profClassOrdinal)
				+ " name="
				+ profClassName
				+ " dt_ms="
				+ Std.string(dtMs));
		}
		profClassCount = profClassOrdinal;
		final profClassMatch = profileClassFilter != null && profileClassFilter.length > 0 && profClassName == profileClassFilter;
		profileWarnEvery("class", profClassCount, profClassName, classType.pos, 50);
		if (profileVerbose)
			profileLogLine("reflaxe.ocaml: class_begin count=" + Std.string(profClassCount) + " name=" + profClassName);
		#end
		ctx.emittedHaxeModules.set(classType.module, true);
		ctx.currentModuleId = classType.module;
		ctx.currentTypeName = classType.name;
		ctx.resetLocalValueNames();
		ctx.assignedVars.clear();
		// Avoid OS filename limits for `@:generic` specializations by hashing long module ids.
		// Only apply the override when needed so we don't accidentally diverge from Reflaxe's
		// default `BaseType.moduleId()` naming for normal modules.
		final moduleFileId = ctx.fileIdForModuleId(classType.module);
		if (ctx.fileIdOverrideByModuleId.exists(classType.module) || ctx.modulePrefix != null) {
			setOutputFileName(moduleFileId);
		}
		#if macro
		ctx.currentIsHaxeStd = isPosInHaxeStd(classType.pos);
		#end

		final mainModule = getMainModule();
		final isMain = switch (mainModule) {
			case TClassDecl(clsRef): final m = clsRef.get(); (m.module == classType.module) && (m.name == classType.name);
			case _: false;
		}
		if (hasStaticMainMethod(funcFields)) {
			recordStaticMainCandidate(classType.module, moduleFileId, classType.name);
		}
		if (isMain) {
			mainModuleId = moduleFileId;
		}

		final fullName = (classType.pack ?? []).concat([classType.name]).join(".");
		ctx.currentTypeFullName = fullName;
		ctx.classTagsByFullName.set(fullName, classTagsForClassType(classType));
		#if macro
		// Seed reflection metadata for `Type.createInstance` (M10).
		//
		// We capture the constructor signature and defining module id so that the
		// generated `HxTypeRegistry.init()` can register a per-class constructor
		// closure capable of:
		// - validating required arity,
		// - padding omitted optional args with `hx_null`,
		// - unboxing dynamic primitives.
		ctx.classModuleIdByFullName.set(fullName, classType.module);
		// Haxe classes are instantiable by default, even if they only define static members.
		// Some compiler paths expose `classType.constructor == null` for those, but `new C()`
		// and `Type.createInstance(C, [])` must still work. Treat missing constructor info
		// as an implicit `new():Void` for non-extern, non-interface classes.
		final isOcamlNativeSurface = classType.pack != null && classType.pack.length > 0 && classType.pack[0] == "ocaml";
		final hasCtor = (!classType.isInterface) && (!classType.isExtern) && (!isOcamlNativeSurface);
		ctx.ctorPresentByFullName.set(fullName, hasCtor);
		final ctorArgs:Null<Array<{name:String, opt:Bool, t:Type}>> = if (!hasCtor) {
			null;
		} else {
			if (classType.constructor == null) {
				[];
			} else {
				final ctorField = classType.constructor.get();
				switch (TypeTools.follow(ctorField.type)) {
					case TFun(args, _): args;
					case _: [];
				}
			}
		}
		if (!hasCtor) {
			ctx.ctorArgsByFullName.remove(fullName);
		} else {
			ctx.ctorArgsByFullName.set(fullName, ctorArgs != null ? ctorArgs : []);
		}
		#end

		// `Type.getInstanceFields` / `Type.getClassFields` registry seeds (M10).
		//
		// We record direct field names here, then compute inherited instance fields when
		// generating `HxTypeRegistry.ml` at the end of compilation (after DCE/filtering).
		#if macro
		{
			final inst:Array<String> = [];
			final stat:Array<String> = [];
			for (v in varFields) {
				final n = v.field.name;
				if (n == "new")
					continue;
				(v.isStatic ? stat : inst).push(n);
			}
			for (f in funcFields) {
				final n = f.field.name;
				if (n == "new")
					continue;
				(f.isStatic ? stat : inst).push(n);
			}
			inst.sort(Reflect.compare);
			stat.sort(Reflect.compare);
			ctx.directInstanceFieldsByFullName.set(fullName, inst);
			ctx.directStaticFieldsByFullName.set(fullName, stat);
		}
		#end
		#if macro
		if (!ctx.currentIsHaxeStd || haxe.macro.Context.defined("reflaxe_ocaml_full_type_registry")) {
			ctx.nonStdTypeRegistryClasses.set(fullName, true);
		}
		#end
		if (classType.superClass != null) {
			final sup = classType.superClass.t.get();
			ctx.currentSuperFullName = (sup.pack ?? []).concat([sup.name]).join(".");
			ctx.currentSuperModuleId = sup.module;
			ctx.currentSuperTypeName = sup.name;
			ctx.currentSuperCtorArgs = null;
			#if macro
			ctx.superByFullName.set(fullName, ctx.currentSuperFullName);
			#end
			if (sup.constructor != null) {
				final ctorField = sup.constructor.get();
				switch (TypeTools.follow(ctorField.type)) {
					case TFun(args, _):
						ctx.currentSuperCtorArgs = args;
					case _:
				}
			}
		} else {
			ctx.currentSuperFullName = null;
			ctx.currentSuperModuleId = null;
			ctx.currentSuperTypeName = null;
			ctx.currentSuperCtorArgs = null;
			#if macro
			ctx.superByFullName.remove(fullName);
			#end
		}

		// Guardrails (M5+): fail fast for features we haven't implemented.
		#if macro
		if (!ctx.currentIsHaxeStd) {
			final problems:Array<String> = [];

			if (problems.length > 0) {
				haxe.macro.Context.error("reflaxe.ocaml (M5): unsupported OO feature(s) in '"
					+ fullName
					+ "': "
					+ problems.join("; ")
					+ ".\nSupported for now: single inheritance (`extends`) and interfaces (`implements`). (bd: haxe.ocaml-dwt.1.2)",
					classType.pos);
			}
		}
		#end

		final items:Array<OcamlModuleItem> = [];
		#if macro
		final sourceMapValue = haxe.macro.Context.definedValue("ocaml_sourcemap");
		final emitSourceMap = haxe.macro.Context.defined("ocaml_sourcemap")
			&& (sourceMapValue == null || sourceMapValue.length == 0 || sourceMapValue == "1" || sourceMapValue == "directives");
		#else
		final emitSourceMap = false;
		#end
		final builder = new OcamlBuilder(ctx, ocamlTypeExprFromHaxeType, functionPlanRegistry, representationRegistry, staticStoragePlan, emitSourceMap);

		// Header marker as a no-op binding to keep output non-empty and debuggable.
		items.push(OcamlModuleItem.ILet([
			{
				name: "__reflaxe_ocaml__",
				expr: OcamlExpr.EConst(OcamlConst.CUnit)
			}
		], false));

		final lets:Array<OcamlLetBinding> = [];

		// Instance surface (M5): record type + create + instance methods.
		final instanceVarsLocal = varFields.filter(v -> !v.isStatic);
		final hasInstanceVarsLocal = instanceVarsLocal.length > 0;

		// Default expressions are only available via `ClassVarData` for the class currently being compiled.
		// For inherited vars (declared in super classes), we fall back to `defaultValueForType`.
		final localVarInitByName:Map<String, TypedExpr> = [];
		for (v in instanceVarsLocal) {
			final init = v.findDefaultExpr();
			if (init != null)
				localVarInitByName.set(v.field.name, init);
		}

		var ctorFunc:Null<ClassFuncData> = null;
		final instanceMethods:Array<ClassFuncData> = [];
		for (f in funcFields) {
			if (f.expr == null)
				continue;
			if (f.isStatic)
				continue;
			if (f.field.name == "new") {
				ctorFunc = f;
			} else {
				instanceMethods.push(f);
			}
		}
		for (method in instanceMethods) {
			if (method.field.name != "toString")
				continue;
			switch (TypeTools.follow(method.field.type)) {
				case TFun(arguments, result) if (arguments.length == 0 && OcamlRepresentationRegistry.isExactString(result)):
					ctx.dynamicStringifierByFullName.set(fullName, {
						moduleId: classType.module,
						sourceTypeName: classType.name,
						targetMethodName: ctx.scopedValueName(classType.module, classType.name,
							ctx.dispatchTypes.exists(fullName) ? method.field.name + "__impl" : method.field.name)
					});
				case _:
			}
		}

		// Interface dispatch surface (M10 strict portable):
		//
		// We do not emit constructors/implementations for interfaces, but we do emit a
		// record type carrying method fields so interface-typed callsites can annotate
		// receivers with a concrete OCaml type (`ifoo_t`) instead of failing with
		// "unbound type constructor".
		if (classType.isInterface && !isOcamlNativeSurface) {
			function buildDispatchMethodType(haxeMethodType:Type):OcamlTypeExpr {
				final selfT = OcamlTypeExpr.TIdent("Obj.t");
				return switch (haxeMethodType) {
					case TFun(args, ret):
						var outT = ocamlTypeExprFromHaxeType(ret);
						if (args.length == 0) {
							outT = OcamlTypeExpr.TArrow(OcamlTypeExpr.TIdent("unit"), outT);
						} else {
							for (i in 0...args.length) {
								final a = args[args.length - 1 - i];
								outT = OcamlTypeExpr.TArrow(ocamlTypeExprFromHaxeType(a.t), outT);
							}
						}
						OcamlTypeExpr.TArrow(selfT, outT);
					case _:
						OcamlTypeExpr.TIdent("Obj.t");
				}
			}

			function collectInterfaceMethodFields(iface:ClassType, order:Array<String>, byName:Map<String, ClassField>, seen:Map<String, Bool>):Void {
				for (edge in iface.interfaces) {
					collectInterfaceMethodFields(edge.t.get(), order, byName, seen);
				}
				for (field in iface.fields.get()) {
					if (field == null)
						continue;
					switch (field.kind) {
						case FMethod(_):
							if (!seen.exists(field.name)) {
								seen.set(field.name, true);
								order.push(field.name);
							}
							byName.set(field.name, field);
						case _:
					}
				}
			}

			final interfaceMethodOrder:Array<String> = [];
			final interfaceMethodByName:Map<String, ClassField> = [];
			final interfaceSeen:Map<String, Bool> = [];
			collectInterfaceMethodFields(classType, interfaceMethodOrder, interfaceMethodByName, interfaceSeen);

			if (interfaceMethodOrder.length > 0) {
				final interfaceTypeFields:Array<OcamlTypeRecordField> = [];
				interfaceTypeFields.push({
					name: "__hx_type",
					isMutable: false,
					typ: OcamlTypeExpr.TIdent("Obj.t")
				});
				for (methodName in interfaceMethodOrder) {
					final methodField = interfaceMethodByName.get(methodName);
					if (methodField == null)
						continue;
					interfaceTypeFields.push({
						name: ctx.ocamlRecordLabel(methodName),
						isMutable: false,
						typ: buildDispatchMethodType(methodField.type)
					});
				}
				final instanceTypeName = ctx.scopedInstanceTypeName(classType.module, classType.name);
				items.push(OcamlModuleItem.IType([
					{
						name: instanceTypeName,
						params: [],
						kind: OcamlTypeDeclKind.Record(interfaceTypeFields)
					}
				], false));
			}
		}

		// Any concrete (non-interface) Haxe class is instantiable, even if it only
		// contains static members. The Haxe typer still provides a constructor
		// signature (`classType.constructor`) for the implicit default ctor.
		//
		// We therefore always emit a minimal instance surface (`type t = { __hx_type : Obj.t }`
		// + `create : unit -> t`) for instantiable classes so:
		// - `new C()` can work,
		// - `Type.createInstance(C, [])` can work,
		// - runtime class identity (`Type.getClass`) works consistently.
		final hasImplicitCtor = (!classType.isInterface) && (!classType.isExtern) && (!isOcamlNativeSurface);
		final hasInstanceSurface = hasInstanceVarsLocal || instanceMethods.length > 0 || ctorFunc != null || hasImplicitCtor;
		if (hasInstanceSurface) {
			final instanceTypeName = ctx.scopedInstanceTypeName(classType.module, classType.name);
			final createName = ctx.scopedValueName(classType.module, classType.name, "create");
			final ctorName = ctx.scopedValueName(classType.module, classType.name, "__ctor");

			final isDispatch = !classType.isInterface && ctx.dispatchTypes.exists(fullName);

			// For dynamic dispatch we need a list of all visible instance methods (including inherited)
			// so `obj.foo()` can be lowered to `obj.foo obj ...` regardless of where `foo` was declared.
			final dispatchMethodOrder:Array<String> = [];
			final dispatchMethodDecl:Map<String, {owner:ClassType, field:ClassField}> = [];
			var dispatchLayoutFields:Null<Array<{name:String, kind:String, field:ClassField}>> = null;
			if (isDispatch) {
				function chainFromRoot(c:ClassType):Array<ClassType> {
					final chain:Array<ClassType> = [];
					var cur:Null<ClassType> = c;
					var guard = 0;
					while (cur != null && guard++ < 64) {
						chain.push(cur);
						cur = cur.superClass != null ? cur.superClass.t.get() : null;
					}
					chain.reverse();
					return chain;
				}

				function declaredInstanceMethodFields(c:ClassType):Array<ClassField> {
					final out:Array<ClassField> = [];
					for (cf in c.fields.get()) {
						if (cf == null)
							continue;
						if (cf.name == "new")
							continue;
						switch (cf.kind) {
							case FMethod(_):
								out.push(cf);
							case _:
						}
					}
					return out;
				}

				final chain = chainFromRoot(classType);
				final seen:Map<String, Bool> = [];
				for (c in chain) {
					for (cf in declaredInstanceMethodFields(c)) {
						if (seen.exists(cf.name))
							continue;
						seen.set(cf.name, true);
						dispatchMethodOrder.push(cf.name);
					}
				}
				// Most-derived declaration wins (override).
				for (c in chain) {
					for (cf in declaredInstanceMethodFields(c)) {
						dispatchMethodDecl.set(cf.name, {owner: c, field: cf});
					}
				}

				// Record layout for dispatch instances: preserve a base-prefix layout across
				// the inheritance chain by emitting fields in per-level segments:
				//   (vars introduced at level0), (methods introduced at level0),
				//   (vars introduced at level1), (methods introduced at level1), ...
				//
				// This ensures that accessing inherited method fields through a base static type
				// works even when the runtime value is a subclass record.
				final layout:Array<{name:String, kind:String, field:ClassField}> = [];
				final seenVars:Map<String, Bool> = [];
				final seenMethods2:Map<String, Bool> = [];

				for (c in chain) {
					for (cf in c.fields.get()) {
						if (cf == null)
							continue;
						switch (cf.kind) {
							case FVar(_, _):
								if (seenVars.exists(cf.name))
									continue;
								seenVars.set(cf.name, true);
								layout.push({name: cf.name, kind: "var", field: cf});
							case _:
						}
					}

					for (cf in declaredInstanceMethodFields(c)) {
						if (seenMethods2.exists(cf.name))
							continue;
						seenMethods2.set(cf.name, true);
						layout.push({name: cf.name, kind: "method", field: cf});
					}
				}

				dispatchLayoutFields = layout;
			}

			final isDispatchInstance = isDispatch && dispatchMethodOrder.length > 0;
			function exprMentionsIdent(e:OcamlExpr, target:String):Bool {
				function any(exprs:Array<OcamlExpr>):Bool {
					for (x in exprs)
						if (exprMentionsIdent(x, target))
							return true;
					return false;
				}
				return switch (e) {
					case EPos(_, inner):
						exprMentionsIdent(inner, target);
					case EIdent(n):
						n == target;
					case ERuntimeIdent(reference):
						reference.exactSymbol == target;
					case EConst(_):
						false;
					case ERaw(_):
						false;
					case ERaise(exn):
						exprMentionsIdent(exn, target);
					case ELet(_, value, body, _): exprMentionsIdent(value, target) || exprMentionsIdent(body, target);
					case EFun(_, body):
						exprMentionsIdent(body, target);
					case EApp(fn, args): exprMentionsIdent(fn, target) || any(args);
					case EAppArgs(fn, args): exprMentionsIdent(fn, target) || any(args.map(a -> a.expr));
					case EBinop(_, left, right): exprMentionsIdent(left, target) || exprMentionsIdent(right, target);
					case EUnop(_, expr):
						exprMentionsIdent(expr, target);
					case EIf(cond, thenExpr, elseExpr): exprMentionsIdent(cond,
							target) || exprMentionsIdent(thenExpr, target) || exprMentionsIdent(elseExpr, target);
					case EMatch(scrutinee, cases):
						if (exprMentionsIdent(scrutinee, target)) {
							true;
						} else {
							var found = false;
							for (c in cases) {
								if (exprMentionsIdent(c.expr, target)) {
									found = true;
									break;
								}
								if (c.guard != null && exprMentionsIdent(c.guard, target)) {
									found = true;
									break;
								}
							}
							found;
						}
					case ETry(body, cases):
						if (exprMentionsIdent(body, target)) {
							true;
						} else {
							var found = false;
							for (c in cases) {
								if (exprMentionsIdent(c.expr, target)) {
									found = true;
									break;
								}
								if (c.guard != null && exprMentionsIdent(c.guard, target)) {
									found = true;
									break;
								}
							}
							found;
						}
					case ESeq(exprs):
						any(exprs);
					case EWhile(cond, body): exprMentionsIdent(cond, target) || exprMentionsIdent(body, target);
					case EList(items):
						any(items);
					case ERecord(fields):
						any(fields.map(f -> f.value));
					case EField(expr, _):
						exprMentionsIdent(expr, target);
					case EAssign(_, lhs, rhs): exprMentionsIdent(lhs, target) || exprMentionsIdent(rhs, target);
					case ETuple(items):
						any(items);
					case EAnnot(expr, _):
						exprMentionsIdent(expr, target);
				}
			}

			function paramNameFromPattern(p:OcamlPat):Null<String> {
				return switch (p) {
					case PVar(name):
						name;
					case PAnnot(inner, _):
						paramNameFromPattern(inner);
					case _:
						null;
				}
			}

			function ensureParamUsage(body:OcamlExpr, params:Array<OcamlPat>):OcamlExpr {
				var out = body;
				var i = params.length - 1;
				while (i >= 0) {
					final name = paramNameFromPattern(params[i]);
					if (name != null && name != "_" && !exprMentionsIdent(out, name)) {
						out = OcamlExpr.ESeq([OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [OcamlExpr.EIdent(name)]), out]);
					}
					i -= 1;
				}
				return out;
			}

			final typeFields:Array<OcamlTypeRecordField> = [];

			// Runtime class identity (M10): all class instances carry their most-derived class value
			// in the first record slot so `Type.getClass` can work even through `Obj.magic` upcasts.
			typeFields.push({
				name: "__hx_type",
				isMutable: false,
				typ: OcamlTypeExpr.TIdent("Obj.t")
			});
			if (isDispatchInstance && dispatchLayoutFields != null) {
				function buildDispatchMethodType(haxeMethodType:Type):OcamlTypeExpr {
					// Dispatch methods take `Obj.t` as the receiver so that interface + base-class
					// callsites can share a single representation without OCaml structural subtyping.
					final selfT = OcamlTypeExpr.TIdent("Obj.t");
					return switch (haxeMethodType) {
						case TFun(args, ret):
							var outT = ocamlTypeExprFromHaxeType(ret);
							if (args.length == 0) {
								// Calling convention: `foo()` always supplies `unit` at the callsite in OCaml.
								outT = OcamlTypeExpr.TArrow(OcamlTypeExpr.TIdent("unit"), outT);
							} else {
								for (i in 0...args.length) {
									final a = args[args.length - 1 - i];
									outT = OcamlTypeExpr.TArrow(ocamlTypeExprFromHaxeType(a.t), outT);
								}
							}
							OcamlTypeExpr.TArrow(selfT, outT);
						case _:
							// Should not happen for methods; fall back to a permissive type.
							OcamlTypeExpr.TIdent("Obj.t");
					}
				}
				for (entry in dispatchLayoutFields) {
					switch (entry.kind) {
						case "var":
							typeFields.push({
								name: ctx.ocamlRecordLabel(entry.name),
								isMutable: true,
								typ: instanceFieldCarrier(entry.field.type)
							});
						case "method":
							final info = dispatchMethodDecl.get(entry.name);
							if (info == null)
								continue;
							typeFields.push({
								name: ctx.ocamlRecordLabel(entry.name),
								isMutable: false,
								typ: buildDispatchMethodType(info.field.type)
							});
						case _:
					}
				}
			} else {
				if (hasInstanceVarsLocal) {
					for (v in instanceVarsLocal) {
						typeFields.push({
							name: ctx.ocamlRecordLabel(v.field.name),
							isMutable: true,
							typ: instanceFieldCarrier(v.field.type)
						});
					}
				}
				if (isDispatchInstance) {
					function buildDispatchMethodType(haxeMethodType:Type):OcamlTypeExpr {
						// Dispatch methods take `Obj.t` as the receiver so that interface + base-class
						// callsites can share a single representation without OCaml structural subtyping.
						final selfT = OcamlTypeExpr.TIdent("Obj.t");
						return switch (haxeMethodType) {
							case TFun(args, ret):
								var outT = ocamlTypeExprFromHaxeType(ret);
								if (args.length == 0) {
									// Calling convention: `foo()` always supplies `unit` at the callsite in OCaml.
									outT = OcamlTypeExpr.TArrow(OcamlTypeExpr.TIdent("unit"), outT);
								} else {
									for (i in 0...args.length) {
										final a = args[args.length - 1 - i];
										outT = OcamlTypeExpr.TArrow(ocamlTypeExprFromHaxeType(a.t), outT);
									}
								}
								OcamlTypeExpr.TArrow(selfT, outT);
							case _:
								OcamlTypeExpr.TIdent("Obj.t");
						}
					}

					for (name in dispatchMethodOrder) {
						final info = dispatchMethodDecl.get(name);
						if (info == null)
							continue;
						typeFields.push({
							name: ctx.ocamlRecordLabel(name),
							isMutable: false,
							typ: buildDispatchMethodType(info.field.type)
						});
					}
				}
			}

			final typeDecl:OcamlTypeDecl = {
				name: instanceTypeName,
				params: [],
				kind: OcamlTypeDeclKind.Record(typeFields)
			};
			validateMonomorphicClassLayout(classType, instanceTypeName, typeFields);
			items.push(OcamlModuleItem.IType([typeDecl], false));

			// create: allocate record, run ctor body, return self
			var createParams:Array<OcamlPat> = [OcamlPat.PConst(OcamlConst.CUnit)];
			var ctorBody:OcamlExpr = OcamlExpr.EConst(OcamlConst.CUnit);
			var constructionBoundary:Null<OcamlCallableBoundaryPlan> = null;
			if (ctorFunc != null && ctorFunc.expr != null) {
				final argInfo:Array<{
					id:Int,
					name:String,
					t:Type,
					value:Null<TypedExpr>
				}> = ctorFunc.args.map(a -> ({
					id: a.tvar != null ? a.tvar.id : -1,
					name: a.getName(),
					t: a.type,
					value: a.expr
				}));
				final ctorReturnType:Type = switch (TypeTools.follow(ctorFunc.field.type)) {
					case TFun(_, ret): ret;
					case _: ctorFunc.expr.t;
				};
				final syntaxInput = functionPlanRegistry.functionSyntaxInputFor(ctorFunc);
				constructionBoundary = syntaxInput.constructionBoundary;
				switch (builder.buildFunctionFromArgsAndExpr(argInfo, ctorFunc.expr, syntaxInput.plan, syntaxInput.localIdentities, ctorReturnType)) {
					case OcamlExpr.EFun(params, body):
						createParams = params;
						ctorBody = body;
					case _:
				}
				if (constructionBoundary != null) {
					final result = constructionBoundary.result;
					if (createParams.length != constructionBoundary.arguments.length
						|| result == null
						|| result.outputCarrierTypeId != instanceTypeName) {
						throw 'reflaxe.ocaml [ocaml-call:construction-emission-mismatch]: admitted constructor "${constructionBoundary.calleeId}" does not match create(${createParams.length}) -> $instanceTypeName';
					}
				}
			}

			final selfInit:OcamlExpr = if (hasInstanceVarsLocal || isDispatchInstance) {
				final fields:Array<OcamlRecordField> = [];
				fields.push({
					name: "__hx_type",
					value: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "class_"), [OcamlExpr.EConst(OcamlConst.CString(fullName))])
				});
				if (isDispatchInstance && dispatchLayoutFields != null) {
					function wrapperFor(owner:ClassType, methodType:Type, ownerBindingName:String):OcamlExpr {
						final ownerExpr = owner.module == classType.module ? OcamlExpr.EIdent(ownerBindingName) : OcamlExpr.EField(OcamlExpr.EIdent(moduleIdToOcamlModuleName(owner.module)),
							ownerBindingName);

						final args:Null<Array<{name:String, opt:Bool, t:Type}>> = switch (methodType) {
							case TFun(fargs, _): fargs;
							case _: null;
						}

						final params:Array<OcamlPat> = [OcamlPat.PVar("o")];
						final callArgs:Array<OcamlExpr> = [OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EIdent("o")])];

						if (args == null || args.length == 0) {
							// `foo()` call convention: include `unit`.
							params.push(OcamlPat.PConst(OcamlConst.CUnit));
							callArgs.push(OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EConst(OcamlConst.CUnit)]));
						} else {
							for (i in 0...args.length) {
								final n = "a" + Std.string(i);
								params.push(OcamlPat.PVar(n));
								callArgs.push(OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EIdent(n)]));
							}
						}

						return OcamlExpr.EFun(params, OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EApp(ownerExpr, callArgs)]));
					}

					for (entry in dispatchLayoutFields) {
						switch (entry.kind) {
							case "var":
								final init = localVarInitByName.exists(entry.name) ? localVarInitByName.get(entry.name) : null;
								final value = init != null ? buildStandaloneExpression(builder, fieldInitializerOwner(classType, entry.field, "instance"),
									init) : instanceFieldDefault(entry.field.type);
								fields.push({name: ctx.ocamlRecordLabel(entry.name), value: value});
							case "method":
								final info = dispatchMethodDecl.get(entry.name);
								if (info == null)
									continue;
								final owner = info.owner;
								final ownerBinding = ctx.scopedValueName(owner.module, owner.name, entry.name + "__impl");
								final value = wrapperFor(owner, info.field.type, ownerBinding);
								fields.push({name: ctx.ocamlRecordLabel(entry.name), value: value});
							case _:
						}
					}
				} else {
					for (v in instanceVarsLocal) {
						final init = v.findDefaultExpr();
						final value = init != null ? buildStandaloneExpression(builder, fieldInitializerOwner(classType, v.field, "instance"),
							init) : instanceFieldDefault(v.field.type);
						fields.push({name: ctx.ocamlRecordLabel(v.field.name), value: value});
					}
					if (isDispatchInstance) {
						function wrapperFor(owner:ClassType, methodType:Type, ownerBindingName:String):OcamlExpr {
							final ownerExpr = owner.module == classType.module ? OcamlExpr.EIdent(ownerBindingName) : OcamlExpr.EField(OcamlExpr.EIdent(moduleIdToOcamlModuleName(owner.module)),
								ownerBindingName);

							final args:Null<Array<{name:String, opt:Bool, t:Type}>> = switch (methodType) {
								case TFun(fargs, _): fargs;
								case _: null;
							}

							final params:Array<OcamlPat> = [OcamlPat.PVar("o")];
							final callArgs:Array<OcamlExpr> = [OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EIdent("o")])];

							if (args == null || args.length == 0) {
								params.push(OcamlPat.PConst(OcamlConst.CUnit));
								callArgs.push(OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EConst(OcamlConst.CUnit)]));
							} else {
								for (i in 0...args.length) {
									final n = "a" + Std.string(i);
									params.push(OcamlPat.PVar(n));
									callArgs.push(OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EIdent(n)]));
								}
							}

							return OcamlExpr.EFun(params, OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EApp(ownerExpr, callArgs)]));
						}

						for (name in dispatchMethodOrder) {
							final info = dispatchMethodDecl.get(name);
							if (info == null)
								continue;
							final owner = info.owner;
							final ownerBinding = ctx.scopedValueName(owner.module, owner.name, name + "__impl");
							final value = wrapperFor(owner, info.field.type, ownerBinding);
							fields.push({name: ctx.ocamlRecordLabel(name), value: value});
						}
					}
				}

				// Dune defaults can be warning-as-error; avoid `unused-var-strict` for `self`
				// by forcing a use when the body doesn't reference it.
				if (isDispatch) {
					ctorBody = ensureParamUsage(ctorBody, [OcamlPat.PVar("self")]);
				}
				final recordExpr = OcamlExpr.ERecord(fields);
				// Always annotate: `__hx_type` is a shared label across many records, and
				// some classes may otherwise become ambiguous for OCaml's record inference.
				OcamlExpr.EAnnot(recordExpr, OcamlTypeExpr.TIdent(instanceTypeName));
			} else {
				final recordExpr = OcamlExpr.ERecord([
					{
						name: "__hx_type",
						value: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "class_"), [OcamlExpr.EConst(OcamlConst.CString(fullName))])
					}
				]);
				OcamlExpr.EAnnot(recordExpr, OcamlTypeExpr.TIdent(instanceTypeName));
			}

			final createBody = OcamlExpr.ELet("self", selfInit,
				OcamlExpr.ESeq([OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [ctorBody]), OcamlExpr.EIdent("self")]), false);
			lets.push({name: createName, expr: OcamlExpr.EFun(createParams, createBody)});

			// `Type.createEmptyInstance` support (M10): allocate an instance without running
			// the constructor body. This uses the same record initializer as `create`, so the
			// instance has a well-formed `__hx_type` marker and default field values.
			//
			// Note: upstream semantics for field initializers vs constructor execution varies
			// per target; for now, this matches the "default-initialized record" behavior.
			final emptyName = ctx.scopedValueName(classType.module, classType.name, "__empty");
			lets.push({
				name: emptyName,
				expr: OcamlExpr.EFun([OcamlPat.PConst(OcamlConst.CUnit)], selfInit)
			});

			// Dispatch constructor function (used by `super()` lowering). This intentionally mirrors
			// the constructor body used in `create`, but takes `self` explicitly.
			if (isDispatch) {
				final selfPat = OcamlPat.PAnnot(OcamlPat.PVar("self"), OcamlTypeExpr.TIdent(instanceTypeName));
				final ctorBodyForCtor = ensureParamUsage(ctorBody, [selfPat].concat(createParams));
				lets.push({
					name: ctorName,
					expr: OcamlExpr.EFun([selfPat].concat(createParams), OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [ctorBodyForCtor]))
				});
			}

			for (f in instanceMethods) {
				#if macro
				if (profileVerbose && profClassMatch && profileDetail) {
					if (profileFieldFilter == null || profileFieldFilter.length == 0 || profileFieldFilter == f.field.name) {
						profileLogLine("reflaxe.ocaml: field_begin class=" + profClassName + " kind=instance_method name=" + f.field.name);
					}
				}
				#end
				final compiled = {
					final expectedArgs:Null<Array<{name:String, opt:Bool, t:Type}>> = switch (TypeTools.follow(f.field.type)) {
						case TFun(fargs, _): fargs;
						case _: null;
					}
					final argInfo:Array<{
						id:Int,
						name:String,
						t:Type,
						value:Null<TypedExpr>
					}> = f.args.map(a -> ({
						id: a.tvar != null ? a.tvar.id : -1,
						name: a.getName(),
						t: a.type,
						value: a.expr
					}));
					final methodReturnType:Type = switch (TypeTools.follow(f.field.type)) {
						case TFun(_, ret): ret;
						case _: f.expr.t;
					};
					final syntaxInput = functionPlanRegistry.functionSyntaxInputFor(f);
					switch (builder.buildFunctionFromArgsAndExpr(argInfo, f.expr, syntaxInput.plan, syntaxInput.localIdentities, methodReturnType)) {
						case OcamlExpr.EFun(params, b):
							final annotatedParams = if (expectedArgs != null && params.length == expectedArgs.length) {
								final out:Array<OcamlPat> = [];
								for (i in 0...params.length) {
									final p = params[i];
									final t = expectedArgs[i].t;
									final ocamlT = ocamlTypeExprFromHaxeType(t);
									out.push(switch (p) {
										case OcamlPat.PVar(_):
											// Only annotate when we have a concrete OCaml type.
											//
											// Why:
											// - This helps dune/ocamlc resolve record labels and module dependencies (notably for
											//   records-of-functions class encodings), which would otherwise fail with
											//   "Unbound record field ..." during bootstrapping.
											// - However, our portable type mapper intentionally collapses polymorphic cases
											//   (type parameters, function types, many abstracts) to `Obj.t`. Annotating those
											//   would *harm* inference and can break correct code (e.g. generic `StringBuf.add`,
											//   or function-typed parameters like `stop:Void->Bool`).
											//
											// So we only emit annotations when the mapped type is not `Obj.t`.
											(ocamlT == OcamlTypeExpr.TIdent("Obj.t")) ? p : OcamlPat.PAnnot(p, ocamlT);
										case OcamlPat.PAnnot(_, _):
											p;
										case _:
											p;
									});
								}
								out;
							} else {
								params;
							}
							final allParams = [OcamlPat.PVar("self")].concat(annotatedParams);
							final body = ensureParamUsage(b, allParams);
							final unitBody = funReturnsVoid(f.field.type) ? OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [body]) : body;
							OcamlExpr.EFun(allParams, unitBody);
						case _:
							OcamlExpr.EFun([OcamlPat.PVar("self")], OcamlExpr.EConst(OcamlConst.CUnit));
					}
				};
				final methodName = isDispatch ? ctx.scopedValueName(classType.module, classType.name,
					f.field.name + "__impl") : ctx.scopedValueName(classType.module, classType.name, f.field.name);
				final adjusted = if (isDispatch) {
					// Annotate `self` to avoid ambiguous record labels when multiple class records exist in a module.
					switch (compiled) {
						case OcamlExpr.EFun(params, body):
							final selfPat = OcamlPat.PAnnot(OcamlPat.PVar("self"), OcamlTypeExpr.TIdent(instanceTypeName));
							final rest = params.length > 0 ? params.slice(1) : [];
							OcamlExpr.EFun([selfPat].concat(rest), body);
						case _:
							compiled;
					}
				} else {
					compiled;
				}
				lets.push({name: methodName, expr: adjusted});
			}
		}

		// Static functions (M2+)
		for (f in funcFields) {
			if (f.expr == null)
				continue;
			if (!f.isStatic)
				continue;

			#if macro
			if (profileVerbose && profClassMatch && profileDetail) {
				if (profileFieldFilter == null || profileFieldFilter.length == 0 || profileFieldFilter == f.field.name) {
					profileLogLine("reflaxe.ocaml: field_begin class=" + profClassName + " kind=static_method name=" + f.field.name);
				}
			}
			#end

			final name = ctx.scopedValueName(classType.module, classType.name, f.field.name);
			final argInfo:Array<{
				id:Int,
				name:String,
				t:Type,
				value:Null<TypedExpr>
			}> = f.args.map(a -> ({
				id: a.tvar != null ? a.tvar.id : -1,
				name: a.getName(),
				t: a.type,
				value: a.expr
			}));
			#if macro
			final profFieldStartS = (profileVerbose && profClassMatch && profileDetail) ? profileNowS() : 0.0;
			#end
			final staticReturnType:Type = switch (TypeTools.follow(f.field.type)) {
				case TFun(_, ret): ret;
				case _: f.expr.t;
			};
			final syntaxInput = functionPlanRegistry.functionSyntaxInputFor(f);
			final compiled = builder.buildFunctionFromArgsAndExpr(argInfo, f.expr, syntaxInput.plan, syntaxInput.localIdentities, staticReturnType);
			#if macro
			if (profileVerbose && profClassMatch && profileDetail) {
				if (profileFieldFilter == null || profileFieldFilter.length == 0 || profileFieldFilter == f.field.name) {
					final dtMs = Std.int((profileNowS() - profFieldStartS) * 1000);
					profileLogLine("reflaxe.ocaml: field_end class=" + profClassName + " kind=static_method name=" + f.field.name + " dt_ms="
						+ Std.string(dtMs));
				}
			}
			#end

			// `dynamic function` fields are mutable in Haxe: they can be reassigned at runtime
			// (including statics, see upstream Issue5556). Model them like mutable statics:
			// - store as `ref` cell
			// - lower reads to `!x` and writes to `x := v` in the builder.
			final isDynamicMethod = switch (f.field.kind) {
				case FMethod(MethDynamic): true;
				case _: false;
			};
			final storage = isDynamicMethod ? requireStaticStorage(classType, f.field, OcamlStaticStorageKind.DynamicMethod) : null;
			final expr = if (storage != null && storage.declarationSite != OcamlStaticStorageDeclarationSite.OwnerBinding) {
				OcamlExpr.EAssign(OcamlAssignOp.RefSet, OcamlExpr.EIdent(storage.targetValueName), compiled);
			} else if (isDynamicMethod) {
				final t = ocamlTypeExprFromHaxeType(f.field.type);
				OcamlExpr.EApp(OcamlExpr.EIdent("ref"), [OcamlExpr.EAnnot(compiled, t)]);
			} else {
				compiled;
			};
			final bindingName = storage != null
				&& storage.declarationSite != OcamlStaticStorageDeclarationSite.OwnerBinding ? OcamlNameTools.normalizeValueIdentifier("__init_" + name) : name;
			lets.push({name: bindingName, expr: expr});
		}

		// Static vars (M6+)
		//
		// Haxe class-level `static var x = <expr>` becomes a module-level `let x = <expr>`.
		//
		// Note:
		// - This currently models *declaration + initialization* only.
		// - Reassignment semantics (`MyClass.x = v`) require an explicit representation decision
		//   (`ref` vs `mutable record field` vs other), and are handled separately.
		for (v in varFields) {
			if (!v.isStatic)
				continue;
			#if macro
			if (profileVerbose && profClassMatch && profileDetail) {
				if (profileFieldFilter == null || profileFieldFilter.length == 0 || profileFieldFilter == v.field.name) {
					profileLogLine("reflaxe.ocaml: field_begin class=" + profClassName + " kind=static_var name=" + v.field.name);
				}
			}
			#end
			final name = ctx.scopedValueName(classType.module, classType.name, v.field.name);

			// Haxe `static var` is mutable by default. We currently model this uniformly as a
			// `ref` cell in OCaml and lower reads/writes to `!x` / `x := v`.
			//
			// Note: we previously tried to infer mutability by scanning assignments, but
			// upstream tests write to statics from inside methods (e.g. `staticVar = "x"`),
			// and the macro API does not reliably expose all function bodies through
			// `ClassField.expr()` at this stage. Until we have a robust whole-program
			// analysis over the same typed tree we codegen from, we keep the semantics
			// correct by treating all static vars as mutable. (bd: haxe.ocaml-xgv.3.7)
			final isMutableStatic = !v.field.isFinal;
			final storage = isMutableStatic ? requireStaticStorage(classType, v.field, OcamlStaticStorageKind.Variable) : null;
			// Static var initializers are stored on the field itself (not in the constructor pre-assignments
			// that `ClassVarData.findDefaultExpr()` uses for instance vars).
			final init = v.field.expr();
			final representedStatic = storage == null ? null : requireStaticFieldRepresentation(storage);
			final initT = representedStatic == null ? ocamlTypeExprFromHaxeType(v.field.type) : representedStatic.carrierType;
			final consumesRepresentedNullDefault = representedStatic != null
				&& storage != null
				&& (storage.semanticTypeId == "Null<Int>" || storage.semanticTypeId == "Null<Bool>" || storage.semanticTypeId == "String")
				&& (init == null || isLiteralNullInitializer(init));
			final compiledInitFromFieldType = if (consumesRepresentedNullDefault) {
				representedStatic.implicitDefault;
			} else if (init != null) {
				buildStandaloneAssignment(builder, fieldInitializerOwner(classType, v.field, "static"), v.field.type, init);
			} else {
				representedStatic == null ? defaultValueForType(v.field.type) : representedStatic.implicitDefault;
			};
			final compiledInit = if (consumesRepresentedNullDefault) {
				compiledInitFromFieldType;
			} else {
				switch (initT) {
					case OcamlTypeExpr.TIdent("Obj.t"):
						OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [compiledInitFromFieldType]);
					case _:
						compiledInitFromFieldType;
				}
			}
			final compiled = if (isMutableStatic) {
				if (storage != null && storage.declarationSite != OcamlStaticStorageDeclarationSite.OwnerBinding) {
					OcamlExpr.EAssign(OcamlAssignOp.RefSet, OcamlExpr.EIdent(storage.targetValueName), compiledInit);
				} else {
					// OCaml value restriction: `ref (HxArray.create ())` yields a weak type variable
					// unless we pin the element type. We do that by annotating the initializer with
					// the field's (translated) OCaml type, so the `ref` cell becomes monomorphic.
					// This is especially important for `Array<T>` statics used heavily in macro
					// state. (bd: haxe.ocaml-xgv.2)
					final initExpr = OcamlExpr.EAnnot(compiledInit, initT);
					OcamlExpr.EApp(OcamlExpr.EIdent("ref"), [initExpr]);
				}
			} else {
				compiledInit;
			}
			final bindingName = (storage != null
				&& storage.declarationSite != OcamlStaticStorageDeclarationSite.OwnerBinding) ? OcamlNameTools.normalizeValueIdentifier("__init_" +
					name) : name;
			lets.push({name: bindingName, expr: compiled});
		}
		for (entry in staticStoragePlan.entriesForModule(classType.module)) {
			if (entry.declarationSite != OcamlStaticStorageDeclarationSite.TypePrelude || entry.declarationTypeName != classType.name)
				continue;
			final representedField = requireStaticFieldRepresentation(entry);
			final initialValue = OcamlExpr.EAnnot(representedField == null ? defaultValueForType(entry.fieldType) : representedField.implicitDefault,
				representedField == null ? entry.carrierType : representedField.carrierType);
			items.push(OcamlModuleItem.ILet([
				{
					name: entry.targetValueName,
					expr: OcamlExpr.EApp(OcamlExpr.EIdent("ref"), [initialValue])
				}
			], false));
		}

		if (lets.length > 0) {
			#if macro
			if (profileVerbose && profClassMatch)
				profileLogLine("reflaxe.ocaml: class_binding_order_begin class=" + profClassName + " bindings=" + Std.string(lets.length));
			#end
			for (g in orderLetBindingsForOcaml(lets)) {
				items.push(OcamlModuleItem.ILet(g.bindings, g.isRec));
			}
			#if macro
			if (profileVerbose && profClassMatch)
				profileLogLine("reflaxe.ocaml: class_binding_order_end class=" + profClassName);
			#end
		}
		#if macro
		if (profileVerbose && profClassMatch)
			profileLogLine("reflaxe.ocaml: class_runtime_scan_begin class=" + profClassName + " items=" + Std.string(items.length));
		#end
		RuntimeUsageCollector.collectFromModuleItems(items, (moduleName) -> ctx.markRuntimeModule(moduleName));
		#if macro
		if (profileVerbose && profClassMatch)
			profileLogLine("reflaxe.ocaml: class_runtime_scan_end class=" + profClassName);
		#end

		var out = "(* Generated by reflaxe.ocaml (WIP) *)\n(* Haxe type: " + fullName + " *)\n\n";
		final printStartS = #if macro (profileVerbose && profClassMatch) ? profileNowS() : 0.0 #else 0.0 #end;
		#if macro
		if (profileVerbose && profClassMatch)
			profileLogLine("reflaxe.ocaml: class_print_begin class=" + profClassName);
		#end
		final printed = printer.printModule(items);
		final printEndS = #if macro (profileVerbose && profClassMatch) ? profileNowS() : 0.0 #else 0.0 #end;
		out += printed;
		#if macro
		if (profileVerbose && profClassMatch) {
			final dtMs = Std.int((printEndS - printStartS) * 1000);
			profileLogLine("reflaxe.ocaml: class_print class=" + profClassName + " dt_ms=" + Std.string(dtMs) + " chars="
				+ Std.string(printed != null ? printed.length : 0));
		}
		if (profileVerbose) {
			final classEndS = profileNowS();
			final dtMs = Std.int((classEndS - profClassStartS) * 1000);
			profileLogLine("reflaxe.ocaml: class_end count=" + Std.string(profClassCount) + " name=" + profClassName + " dt_ms=" + Std.string(dtMs)
				+ " chars=" + Std.string(out.length));
		}
		#end

		return out;
	}

	/**
		Rejects an incomplete typed-call graph before Reflaxe writes target files.

		Function plans are finalized while Reflaxe adds the complete typed program.
		This hook is the last target-owned boundary before its output manager turns
		the already-built syntax into files, so a missing or conflicting callee
		cannot leave newly generated OCaml source behind.
	**/
	public override function generateFiles():Void {
		functionPlanRegistry.validateCallGraph();
		super.generateFiles();
	}

	/**
		Clears post-publication native work and rejects incompatible output modes
		before a fresh compiler request starts writing its private source tree.

		`Context.error` terminates macro generation instead of behaving like an
		ordinary target exception. Configuration errors that can be known here
		must therefore fail before Reflaxe opens an output transaction; otherwise
		the framework cannot run its normal candidate-abort path.
	**/
	public override function onCompileStart():Void {
		pendingPublishedOutputBuild = null;
		semanticRuntimeAuthority = null;
		nativeSourceDeclarationAuthority = null;
		#if macro
		if (Context.defined("reflaxe_output_transaction") && Context.defined("ocaml_mli")) {
			Context.error("ocaml_mli cannot run after transactional source publication yet. Disable reflaxe_output_transaction or generate checked interfaces through a separate source-owned step.",
				Context.currentPos());
		}
		#end
	}

	function sealArtifactManifest(artifacts:OcamlArtifactManifestBuilder):Void {
		final runtimeAuthority = semanticRuntimeAuthority;
		final nativeAuthority = nativeSourceDeclarationAuthority;
		if (runtimeAuthority == null || nativeAuthority == null)
			throw "reflaxe.ocaml: source-bundle authorities must be sealed before the artifact manifest";
		artifacts.seal(runtimeAuthority, nativeAuthority);
	}

	/**
		Schedules the same fresh post-publication Dune work for an exact replay.

		The cached payload owns generated source only. Build mode, run intent,
		toolchain diagnostics, and external Dune state remain current-request work.
	**/
	function scheduleReplayBuild(artifacts:OcamlArtifactManifestBuilder):Void {
		#if eval
		if (output == null || output.outputDir == null || output.publicOutputDir == null)
			throw "reflaxe.ocaml: exact replay cannot schedule a build without transactional output paths";
		final noBuild = haxe.macro.Context.defined("ocaml_no_build");
		final emitOnly = haxe.macro.Context.defined("ocaml_emit_only");
		final shouldRun = haxe.macro.Context.defined("ocaml_run");
		if ((noBuild || emitOnly) && !shouldRun)
			return;
		final privateDirectory:String = cast output.outputDir;
		final publicDirectory:String = cast output.publicOutputDir;
		if (Path.normalize(privateDirectory) == Path.normalize(publicDirectory))
			throw "reflaxe.ocaml: exact replay requires a private source transaction before Dune";
		final buildMode = haxe.macro.Context.definedValue("ocaml_build");
		pendingPublishedOutputBuild = {
			publicDirectory: publicDirectory,
			buildDirectory: OcamlDuneBuildState.forOutputDirectory(publicDirectory),
			exeName: DuneProjectEmitter.defaultExeName(publicDirectory),
			mode: buildMode == null ? "native" : buildMode,
			duneLayout: haxe.macro.Context.definedValue("ocaml_dune_layout"),
			run: shouldRun,
			strict: buildMode != null,
			timingReport: haxe.macro.Context.defined("ocaml_build_timing_report"),
			artifacts: artifacts
		};
		#end
	}

	/**
		Runs native work only after transactional source publication succeeds.

		The public generated directory is Dune's workspace root. Reusable Dune
		state lives in a stable sibling, so neither source replacement nor a failed
		Reflaxe candidate can delete it or record a private transaction path.
	**/
	public override function onOutputPublished():Void {
		#if eval
		final pending = pendingPublishedOutputBuild;
		pendingPublishedOutputBuild = null;
		if (pending == null)
			return;
		if (output == null
			|| output.outputDir == null
			|| output.publicOutputDir == null
			|| Path.normalize(output.outputDir) != Path.normalize(pending.publicDirectory)
			|| Path.normalize(output.publicOutputDir) != Path.normalize(pending.publicDirectory)) {
			throw "reflaxe.ocaml: Dune post-publication hook ran before the generated source transaction committed";
		}

		pending.artifacts.continueAtPublishedDirectory(pending.publicDirectory);
		final result = OcamlBuildRunner.tryBuildAndMaybeRun({
			outDir: pending.publicDirectory,
			buildDir: pending.buildDirectory,
			exeName: pending.exeName,
			mode: pending.mode,
			duneLayout: pending.duneLayout,
			run: pending.run,
			strict: pending.strict,
			mli: null,
			mliStrict: false,
			timingReport: pending.timingReport,
			artifacts: pending.artifacts
		});
		// A timing report is volatile evidence rather than source, but its digest
		// still belongs in the target inventory that inspection validates.
		sealArtifactManifest(pending.artifacts);
		switch (result) {
			case Ok(message):
				if (message != null)
					haxe.macro.Context.warning(message, haxe.macro.Context.currentPos());
			case Err(message):
				haxe.macro.Context.error(message, haxe.macro.Context.currentPos());
		}
		OcamlTargetReuseTestHooks.failAfterPublishedWork();
		#end
	}

	public override function onOutputComplete() {
		#if eval
		if (output == null || output.outputDir == null)
			return;
		pendingPublishedOutputBuild = null;
		#if macro
		if (profileEnabled) {
			profileInit();
			final msg = "reflaxe.ocaml: onOutputComplete begin";
			Context.warning(msg, Context.currentPos());
			profileLogLine(msg);
		}
		#end
		final outDir = output.outputDir;
		final revision = programRevision;
		if (revision == null)
			throw "reflaxe.ocaml: cannot seal generated artifacts without a program revision";
		// Keep a second check before artifact sealing in case a future Reflaxe
		// lifecycle adds output-completion work after generateFiles().
		functionPlanRegistry.validateCallGraph();
		final representationDecisions = representationRegistry.decisions();
		for (decision in representationDecisions)
			ctx.recordRepresentationRuntimeRequirements(decision);
		final artifactConfigurationRevision = OcamlArtifactConfigurationRevision.fromMacroContext(OcamlFunctionPlanRegistry.PIPELINE_REVISION,
			DuneProjectEmitter.defaultProjectName(outDir));
		final artifactProfile = OcamlProfileContract.toDefineValue(OcamlProfileContract.fromDefineValue(haxe.macro.Context.definedValue("ocaml_profile")));
		final artifacts = new OcamlArtifactManifestBuilder(outDir, revision.id, artifactConfigurationRevision, artifactProfile);

		// A timing report is tied to one generated-file receipt. Clear the prior
		// revision even when this build will not run Dune or request new timing.
		OcamlBuildTimingReportWriter.clear(outDir);
		#if macro
		if (Context.defined("ocaml_lowering_report")) {
			OcamlLoweringReportWriter.write(outDir, ctx.loweredPlaceReportsSorted(), ctx.runtimeRequirementsSorted(), representationDecisions,
				representationRegistry.representedArrays(), functionPlanRegistry.arrayLiteralProducerDecisions(),
				functionPlanRegistry.anonymousStructureDecisions(), functionPlanRegistry.anonymousStructureOperations(),
				functionPlanRegistry.structuralFieldDecisions(), functionPlanRegistry.localConversions(),
				functionPlanRegistry.containerElementRequiredConversionIds(), functionPlanRegistry.containerElementConversions(),
				functionPlanRegistry.unsafeOperations(), functionPlanRegistry.iMapInterfaceConversions(), functionPlanRegistry.iMapInterfaceCalls(),
				functionPlanRegistry.iMapStorageAliases(), functionPlanRegistry.callDecisions(), functionPlanRegistry.callableBoundaries(),
				functionPlanRegistry.reflectCompareDecisions(), functionPlanRegistry.functionResultBoundaries(), functionPlanRegistry.controlDecisions(),
				functionPlanRegistry.controlLoopTargets(), functionPlanRegistry.controlCatchChains(), functionPlanRegistry.controlAdmissionSnapshots(),
				staticStoragePlan.reportEntries(), staticStoragePlan.revision(), artifacts);
		}
		if (Context.defined("reflaxe_ocaml_semantic_lifecycle_trace")) {
			if (semanticLifecycle == null)
				throw "reflaxe.ocaml: semantic lifecycle tracing was requested without a sealed program/lifecycle";
			OcamlSemanticLifecycleTraceWriter.write(outDir, revision.id, semanticLifecycle.pipelineRevision, getSemanticLifecycleTrace(), artifacts,
				Context.definedValue("reflaxe_ocaml_semantic_lifecycle_trace_function"));
		}
		#end
		final useLineDirectives = #if macro !Context.defined("ocaml_no_line_directives") #else false #end;
		final pluginModeValue = haxe.macro.Context.definedValue("ocaml_plugin_mode");
		final pluginModeEnabled = haxe.macro.Context.defined("ocaml_plugin_mode")
			&& (pluginModeValue == null || StringTools.trim(pluginModeValue) != "0");

		/**
			Plugin packaging can typecheck against the full typed program while omitting selected
			artifacts from the final output directory.

			Why
			- Native plugin artifacts are loaded into a host that may already contain compiler/runtime
			  units such as package aliases or helper registries.
			- We want a hard-cutover filter that applies only to emitted files, not to typing.

			How
			- `ocaml_plugin_mode=1` enables plugin-safe defaults (currently: package aliases are off
			  unless explicitly re-enabled).
			- `ocaml_emit_exclude_packages=a.b,c.d` drops emitted Haxe module units whose package path
			  starts with one of the configured prefixes.
			- `ocaml_emit_exclude_paths=Foo,bar/` prunes emitted artifacts by output-relative path
			  prefix, which also covers root modules without a package path.
		**/
		function normalizeOutputToken(value:String):String {
			var out = value == null ? "" : StringTools.trim(value);
			out = StringTools.replace(out, "\\", "/");
			while (StringTools.startsWith(out, "./"))
				out = out.substr(2);
			return out;
		}

		function parseCsvDefine(name:String):Array<String> {
			final raw = haxe.macro.Context.definedValue(name);
			if (raw == null)
				return [];
			final out:Array<String> = [];
			final seen:Map<String, Bool> = [];
			for (part in raw.split(",")) {
				final trimmed = normalizeOutputToken(part);
				if (trimmed.length == 0 || seen.exists(trimmed))
					continue;
				seen.set(trimmed, true);
				out.push(trimmed);
			}
			return out;
		}

		function startsWithOutputPrefix(candidate:String, prefix:String):Bool {
			final normalizedCandidate = normalizeOutputToken(candidate);
			final normalizedPrefix = normalizeOutputToken(prefix);
			if (normalizedCandidate.length == 0 || normalizedPrefix.length == 0)
				return false;
			final withoutExt = haxe.io.Path.withoutExtension(normalizedCandidate);
			final basename = haxe.io.Path.withoutDirectory(withoutExt);
			return normalizedCandidate == normalizedPrefix
				|| StringTools.startsWith(normalizedCandidate, normalizedPrefix)
				|| withoutExt == normalizedPrefix
				|| StringTools.startsWith(withoutExt, normalizedPrefix)
				|| basename == normalizedPrefix
				|| StringTools.startsWith(basename, normalizedPrefix);
		}

		function modulePackagePath(moduleId:String):String {
			if (moduleId == null || moduleId.length == 0)
				return "";
			final parts = moduleId.split(".");
			if (parts.length <= 1)
				return "";
			parts.pop();
			return parts.join(".");
		}

		function shouldExcludeModuleByPackage(moduleId:String, packagePrefixes:Array<String>):Bool {
			if (packagePrefixes.length == 0)
				return false;
			final packagePath = modulePackagePath(moduleId);
			if (packagePath.length == 0)
				return false;
			for (prefix in packagePrefixes) {
				if (packagePath == prefix || StringTools.startsWith(packagePath, prefix + "."))
					return true;
			}
			return false;
		}

		function moduleOutputCandidates(moduleId:String):Array<String> {
			final fileId = ctx.fileIdForModuleId(moduleId);
			return [
				moduleId,
				StringTools.replace(moduleId, ".", "/"),
				StringTools.replace(moduleId, ".", "_"),
				fileId,
				fileId + ".ml"
			];
		}

		final emitExcludePackagePrefixes = parseCsvDefine("ocaml_emit_exclude_packages");
		final emitExcludePathPrefixes = parseCsvDefine("ocaml_emit_exclude_paths");

		function shouldExcludeModuleOutput(moduleId:String):Bool {
			if (shouldExcludeModuleByPackage(moduleId, emitExcludePackagePrefixes))
				return true;
			if (emitExcludePathPrefixes.length == 0)
				return false;
			for (candidate in moduleOutputCandidates(moduleId)) {
				for (prefix in emitExcludePathPrefixes) {
					if (startsWithOutputPrefix(candidate, prefix))
						return true;
				}
			}
			return false;
		}

		function shouldExcludeOutputPath(relPath:String):Bool {
			if (emitExcludePathPrefixes.length == 0)
				return false;
			for (prefix in emitExcludePathPrefixes) {
				if (startsWithOutputPrefix(relPath, prefix))
					return true;
			}
			return false;
		}

		function collectOutputFilesRecursive(absDir:String, relBase:String, out:Array<String>):Void {
			for (entry in sys.FileSystem.readDirectory(absDir)) {
				final relPath = relBase.length == 0 ? entry : relBase + "/" + entry;
				if (relPath == "_build" || StringTools.startsWith(relPath, "_build/"))
					continue;
				final absPath = haxe.io.Path.join([absDir, entry]);
				if (sys.FileSystem.isDirectory(absPath)) {
					collectOutputFilesRecursive(absPath, relPath, out);
				} else {
					out.push(relPath);
				}
			}
		}

		function pruneEmptyDirectoriesRecursive(absDir:String):Void {
			for (entry in sys.FileSystem.readDirectory(absDir)) {
				final child = haxe.io.Path.join([absDir, entry]);
				if (sys.FileSystem.isDirectory(child))
					pruneEmptyDirectoriesRecursive(child);
			}
			if (absDir == outDir)
				return;
			if (sys.FileSystem.readDirectory(absDir).length == 0)
				sys.FileSystem.deleteDirectory(absDir);
		}

		/**
			Reorder multi-type OCaml compilation units to avoid forward type references.

			Why
			- Haxe allows multiple types per module, and the upstream stdlib sometimes defines enums in an
			  order that creates forward references (e.g. `haxe.macro.Expr.ExprDef` uses `DisplayKind`).
			- In OCaml, type constructors must be defined *before* use unless they are part of a mutually
			  recursive `type ... and ...` group.
			- Reflaxe emits one segment per Haxe type and appends them into a single `.ml` file. Without a
			  post-pass, modules like `haxe.macro.Expr` fail to typecheck under dune:
				`Error: Unbound type constructor displaykind`

			How
			- Split the generated file into per-type segments using the standard header marker.
			- Build a conservative dependency graph between types in the same Haxe module.
			- Stable topological sort segments and rewrite the file in dependency order.

			Notes
			- This is currently applied only to a small whitelist of known multi-type std modules that are
			  required for Stage4 macro-host bring-up. Expand as new modules hit the same limitation.
		**/
		function reorderMlSegmentsByLocalTypeDeps(moduleId:String):Void {
			final fileId = ctx.fileIdForModuleId(moduleId);
			final path = haxe.io.Path.join([outDir, fileId + ".ml"]);
			if (!sys.FileSystem.exists(path))
				return;

			final marker = "(* Generated by reflaxe.ocaml (WIP) *)";
			final content = sys.io.File.getContent(path);
			final firstMarker = content.indexOf(marker);
			if (firstMarker == -1)
				return;

			final prefix = content.substr(0, firstMarker);
			final body = content.substr(firstMarker);
			final rawParts = body.split(marker);
			final segments = new Array<String>();
			for (i in 0...rawParts.length) {
				final p = rawParts[i];
				if (p == null || p.length == 0)
					continue;
				segments.push(marker + p);
			}
			if (segments.length <= 1)
				return;

			function parseSegmentTypeFullName(seg:String):Null<String> {
				final enumPrefix = "(* Haxe enum: ";
				final typePrefix = "(* Haxe type: ";

				var start = seg.indexOf(enumPrefix);
				if (start != -1) {
					start += enumPrefix.length;
					final end = seg.indexOf(" *)", start);
					return end == -1 ? null : seg.substr(start, end - start);
				}

				start = seg.indexOf(typePrefix);
				if (start != -1) {
					start += typePrefix.length;
					final end = seg.indexOf(" *)", start);
					return end == -1 ? null : seg.substr(start, end - start);
				}

				return null;
			}

			function parseSegmentValueBindingNames(seg:String):Array<String> {
				final names:Array<String> = [];
				final seen:Map<String, Bool> = [];
				final re = ~/^[ \t]*let[ \t]+([a-z_][A-Za-z0-9_']*)[ \t]*=/;
				for (line in seg.split("\n")) {
					if (!re.match(line))
						continue;
					final name = re.matched(1);
					if (name != null && !seen.exists(name)) {
						seen.set(name, true);
						names.push(name);
					}
				}
				return names;
			}

			function segmentMentionsIdentifier(seg:String, ident:String):Bool {
				if (ident == null || ident.length == 0)
					return false;
				final escapedBuf = new StringBuf();
				for (i in 0...ident.length) {
					final ch = ident.charAt(i);
					switch (ch) {
						case "\\", "^", "$", ".", "*", "+", "?", "(", ")", "[", "]", "{", "}", "|":
							escapedBuf.add("\\");
							escapedBuf.add(ch);
						case _:
							escapedBuf.add(ch);
					}
				}
				final escaped = escapedBuf.toString();
				final pattern = "(^|[^A-Za-z0-9_'])" + escaped + "([^A-Za-z0-9_']|$)";
				return new EReg(pattern, "m").match(seg);
			}

			final segByFullName:Map<String, String> = [];
			final originalIndex:Map<String, Int> = [];
			final segmentFullNamesInOrder:Array<String> = [];
			final passthrough = new Array<String>();
			for (i in 0...segments.length) {
				final seg = segments[i];
				final fullName = parseSegmentTypeFullName(seg);
				if (fullName == null) {
					passthrough.push(seg);
					continue;
				}
				segByFullName.set(fullName, seg);
				originalIndex.set(fullName, i);
				segmentFullNamesInOrder.push(fullName);
			}

			if (segByFullName.keys().hasNext() == false)
				return;

			function fullNameOfBaseType(bt:BaseType):String {
				return (bt.pack ?? []).concat([bt.name]).join(".");
			}

			function addLocalTypeDepsFromType(t:Type, deps:Map<String, Bool>):Void {
				if (t == null)
					return;
				switch (t) {
					case TMono(r):
						final v = r.get();
						if (v != null)
							addLocalTypeDepsFromType(v, deps);
					case TLazy(f):
						addLocalTypeDepsFromType(f(), deps);
					case TDynamic(t2):
						if (t2 != null)
							addLocalTypeDepsFromType(t2, deps);
					case TAbstract(aRef, params):
						final a = aRef.get();
						if (a != null && a.module == moduleId) {
							final n = fullNameOfBaseType(a);
							if (segByFullName.exists(n))
								deps.set(n, true);
						}
						if (params != null)
							for (p in params)
								addLocalTypeDepsFromType(p, deps);
					case TEnum(eRef, params):
						final e = eRef.get();
						if (e != null && e.module == moduleId) {
							final n = fullNameOfBaseType(e);
							if (segByFullName.exists(n))
								deps.set(n, true);
						}
						if (params != null)
							for (p in params)
								addLocalTypeDepsFromType(p, deps);
					case TInst(cRef, params):
						final c = cRef.get();
						if (c != null && c.module == moduleId) {
							final n = fullNameOfBaseType(c);
							if (segByFullName.exists(n))
								deps.set(n, true);
						}
						if (params != null)
							for (p in params)
								addLocalTypeDepsFromType(p, deps);
					case TType(tRef, params):
						final tt = tRef.get();
						if (tt != null && tt.module == moduleId) {
							final n = fullNameOfBaseType(tt);
							if (segByFullName.exists(n))
								deps.set(n, true);
						}
						if (params != null)
							for (p in params)
								addLocalTypeDepsFromType(p, deps);
					case TAnonymous(aRef):
						final a = aRef.get();
						if (a != null) {
							for (f in a.fields)
								addLocalTypeDepsFromType(f.type, deps);
						}
					case TFun(args, ret):
						for (a in args)
							addLocalTypeDepsFromType(a.t, deps);
						addLocalTypeDepsFromType(ret, deps);
				}
			}

			final depsByFullName:Map<String, Map<String, Bool>> = [];
			final nodes = new Array<String>();
			try {
				for (t in Context.getModule(moduleId)) {
					switch (t) {
						case TEnum(eRef, _):
							final e = eRef.get();
							final n = fullNameOfBaseType(e);
							if (!segByFullName.exists(n))
								continue;
							nodes.push(n);
							final deps:Map<String, Bool> = [];
							for (_ => ctor in e.constructs)
								addLocalTypeDepsFromType(ctor.type, deps);
							// Remove self-dep if present.
							deps.remove(n);
							depsByFullName.set(n, deps);
						case TInst(cRef, _):
							final c = cRef.get();
							final n = fullNameOfBaseType(c);
							if (!segByFullName.exists(n))
								continue;
							nodes.push(n);
							final deps:Map<String, Bool> = [];
							for (f in c.fields.get())
								addLocalTypeDepsFromType(f.type, deps);
							for (f in c.statics.get())
								addLocalTypeDepsFromType(f.type, deps);
							if (c.constructor != null)
								addLocalTypeDepsFromType(c.constructor.get().type, deps);
							if (c.superClass != null)
								addLocalTypeDepsFromType(TInst(c.superClass.t, c.superClass.params), deps);
							// Remove self-dep if present.
							deps.remove(n);
							depsByFullName.set(n, deps);
						case _:
					}
				}
			} catch (_:Dynamic) {
				// If we cannot introspect the module, fall back to the original on-disk order.
				return;
			}

			final nodeSet:Map<String, Bool> = [];
			for (n in nodes)
				nodeSet.set(n, true);

			// Keep generated helper segments (not exposed by Context.getModule) in the graph so they are
			// preserved and can participate in dependency ordering.
			for (fullName in segmentFullNamesInOrder) {
				if (!nodeSet.exists(fullName)) {
					nodes.push(fullName);
					nodeSet.set(fullName, true);
				}
			}

			if (nodes.length == 0)
				return;

			for (n in nodes) {
				if (depsByFullName.get(n) == null)
					depsByFullName.set(n, []);
			}

			// Add conservative value-level dependencies between segment-local top-level `let` bindings.
			// This catches cross-type forward references within a single `.ml` unit (e.g. helper segment
			// calling a value defined in another segment).
			final ownerByValueName:Map<String, String> = [];
			final ambiguousValueName:Map<String, Bool> = [];
			for (fullName in segmentFullNamesInOrder) {
				final seg = segByFullName.get(fullName);
				if (seg == null)
					continue;
				for (name in parseSegmentValueBindingNames(seg)) {
					if (ambiguousValueName.exists(name))
						continue;
					if (ownerByValueName.exists(name)) {
						final owner = ownerByValueName.get(name);
						if (owner != fullName) {
							ownerByValueName.remove(name);
							ambiguousValueName.set(name, true);
						}
					} else {
						ownerByValueName.set(name, fullName);
					}
				}
			}
			for (fullName in segmentFullNamesInOrder) {
				final seg = segByFullName.get(fullName);
				final deps = depsByFullName.get(fullName);
				if (seg == null || deps == null)
					continue;
				for (valueName in ownerByValueName.keys()) {
					final owner = ownerByValueName.get(valueName);
					if (owner == null || owner == fullName)
						continue;
					if (segmentMentionsIdentifier(seg, valueName))
						deps.set(owner, true);
				}
				deps.remove(fullName);
			}

			// Stable Kahn topological sort (ties broken by original segment order).
			final indegree:Map<String, Int> = [];
			for (n in nodes)
				indegree.set(n, 0);
			for (n in nodes) {
				final deps = depsByFullName.get(n);
				if (deps == null)
					continue;
				for (d in deps.keys()) {
					if (!indegree.exists(d))
						continue;
					indegree.set(n, indegree.get(n) + 1);
				}
			}

			function nodeOrderKey(n:String):Int {
				final i = originalIndex.get(n);
				return i == null ? 0 : i;
			}

			final queue = nodes.filter(n -> indegree.get(n) == 0);
			queue.sort((a, b) -> Reflect.compare(nodeOrderKey(a), nodeOrderKey(b)));

			final sorted = new Array<String>();
			while (queue.length > 0) {
				final n = queue.shift();
				sorted.push(n);

				for (m in nodes) {
					final deps = depsByFullName.get(m);
					if (deps == null || !deps.exists(n))
						continue;
					final next = indegree.get(m) - 1;
					indegree.set(m, next);
					if (next == 0) {
						queue.push(m);
						queue.sort((a, b) -> Reflect.compare(nodeOrderKey(a), nodeOrderKey(b)));
					}
				}
			}

			// Cycle fallback: preserve original order.
			if (sorted.length != nodes.length)
				return;

			final out = new StringBuf();
			out.add(prefix);
			for (n in sorted) {
				final seg = segByFullName.get(n);
				if (seg != null)
					out.add(seg);
			}
			// Preserve unknown segments deterministically (original order).
			for (seg in passthrough)
				out.add(seg);
			sys.io.File.saveContent(path, out.toString());
		}

		// Stage4 macro-host bring-up requires compiling upstream `haxe.macro.Expr` under dune.
		reorderMlSegmentsByLocalTypeDeps("haxe.macro.Expr");
		// Stage4 macro-host bring-up also requires compiling `haxe.macro.Type` (many mutually-referencing enums).
		reorderMlSegmentsByLocalTypeDeps("haxe.macro.Type");
		// Portable stdlib closure: `haxe.io.ArrayBufferView` mixes helper/value segments that can
		// reference class values emitted later in the same unit (`create`), so reorder by local deps.
		reorderMlSegmentsByLocalTypeDeps("haxe.io.ArrayBufferView");

		final excludedModuleIds:Map<String, Bool> = [];
		final excludedFrameworkPaths:Map<String, Bool> = [];
		for (moduleId => _ in ctx.emittedHaxeModules) {
			if (!shouldExcludeModuleOutput(moduleId))
				continue;
			excludedModuleIds.set(moduleId, true);
		}
		for (moduleId => _ in excludedModuleIds) {
			ctx.emittedHaxeModules.remove(moduleId);
			final moduleRelativePath = ctx.fileIdForModuleId(moduleId) + ".ml";
			excludedFrameworkPaths.set(moduleRelativePath, true);
			final modulePath = haxe.io.Path.join([outDir, moduleRelativePath]);
			if (sys.FileSystem.exists(modulePath) && !sys.FileSystem.isDirectory(modulePath))
				sys.FileSystem.deleteFile(modulePath);
		}

		#if macro
		if (profileEnabled) {
			final now = profileNowS();
			final msg = "reflaxe.ocaml: onOutputComplete after reorder dt=" + Std.string(Math.round(now - profileStartS)) + "s";
			Context.warning(msg, Context.currentPos());
			profileLogLine(msg);
		}
		#end

		// Type registry (M10): allow `Type.resolveClass/resolveEnum` to work with runtime strings.
		//
		// We intentionally keep this conservative for now (non-stdlib only) to avoid bloating
		// small outputs. Expand once upstream suite running is in scope. (bd: haxe.ocaml-eli)
		{
			final classNames:Array<String> = [];
			for (k in ctx.nonStdTypeRegistryClasses.keys()) {
				final modId = ctx.classModuleIdByFullName.get(k);
				if (modId != null && excludedModuleIds.exists(modId))
					continue;
				classNames.push(k);
			}
			classNames.sort(Reflect.compare);

			final enumNames:Array<String> = [];
			for (k in ctx.nonStdTypeRegistryEnums.keys()) {
				final modId = ctx.enumModuleIdByFullName.get(k);
				if (modId != null && excludedModuleIds.exists(modId))
					continue;
				enumNames.push(k);
			}
			enumNames.sort(Reflect.compare);

			// Typed catches (M10): runtime tag sets per compiled class, used to implement
			// `catch (e:T)` when the thrown value is typed as a supertype (or `Dynamic`).
			final classTagNames:Array<String> = [];
			for (k in ctx.classTagsByFullName.keys()) {
				final modId = ctx.classModuleIdByFullName.get(k);
				if (modId != null && excludedModuleIds.exists(modId))
					continue;
				classTagNames.push(k);
			}
			classTagNames.sort(Reflect.compare);
			var usesDynamicArgArrays = false;
			var usesOptionalNullPadding = false;
			var usesOptionalStringNullPadding = false;
			var usesRuntimeUnbox = false;

			function ocamlStringLiteral(s:String):String {
				return "\"" + escapeOcamlString(s) + "\"";
			}

			function computeInstanceFields(fullName:String):Array<String> {
				final out:Array<String> = [];
				final seen:Map<String, Bool> = [];
				var cur:Null<String> = fullName;
				var guard = 0;
				while (cur != null && guard < 1000) {
					guard++;
					final direct = ctx.directInstanceFieldsByFullName.get(cur);
					if (direct != null) {
						for (f in direct) {
							if (!seen.exists(f)) {
								seen.set(f, true);
								out.push(f);
							}
						}
					}
					cur = ctx.superByFullName.get(cur);
				}
				out.sort(Reflect.compare);
				return out;
			}

			function computeStaticFields(fullName:String):Array<String> {
				final direct = ctx.directStaticFieldsByFullName.get(fullName);
				final out = direct != null ? direct.copy() : [];
				out.sort(Reflect.compare);
				return out;
			}

			final enumLayouts:Array<OcamlTypeRegistryEnumLayout> = [];
			for (name in enumNames) {
				final layouts = ctx.enumConstructorLayoutsByFullName.get(name);
				if (layouts == null)
					continue;
				for (layout in layouts)
					enumLayouts.push({
						enumName: name,
						constructorName: layout.name,
						haxeIndex: layout.haxeIndex,
						ocamlTag: layout.ocamlTag,
						carriesPayload: layout.carriesPayload
					});
			}

			final emptyConstructors:Array<OcamlTypeRegistryEmptyConstructor> = [];
			for (name in classNames) {
				final hasCtor = ctx.ctorPresentByFullName.exists(name) && ctx.ctorPresentByFullName.get(name) == true;
				if (!hasCtor)
					continue;
				final moduleId = ctx.classModuleIdByFullName.get(name);
				if (moduleId == null)
					continue;
				final parts = name.split(".");
				if (parts.length == 0)
					continue;
				final typeName = parts[parts.length - 1];
				emptyConstructors.push({
					className: name,
					moduleName: moduleIdToOcamlModuleName(moduleId),
					targetFunctionName: ctx.scopedValueName(moduleId, typeName, "__empty")
				});
			}

			final classFields:Array<OcamlTypeRegistryClassFields> = [];
			for (name in classNames)
				classFields.push({
					className: name,
					instanceFields: computeInstanceFields(name),
					staticFields: computeStaticFields(name)
				});

			final classSupers:Array<OcamlTypeRegistryClassSuper> = [];
			for (name in classNames) {
				final superName = ctx.superByFullName.get(name);
				if (superName != null)
					classSupers.push({className: name, superName: superName});
			}

			final classTags:Array<OcamlTypeRegistryClassTags> = [];
			for (name in classTagNames) {
				final tags = ctx.classTagsByFullName.get(name);
				if (tags == null)
					continue;
				final sortedTags = tags.copy();
				sortedTags.sort(Reflect.compare);
				classTags.push({className: name, tags: sortedTags});
			}

			final dynamicStringifierNames = [for (name in ctx.dynamicStringifierByFullName.keys()) name];
			dynamicStringifierNames.sort(Reflect.compare);
			final programIdentifiers:Array<OcamlTypeRegistryProgramIdentifier> = [];
			final constructorRuntimeUses:Array<OcamlTypeRegistryRuntimeUse> = [];
			function addConstructorRuntimeUse(id:String, exactSymbol:String, capability:String):Void {
				constructorRuntimeUses.push({id: id, exactSymbol: exactSymbol, capability: capability});
			}
			function planConstructorArgumentRuntimeUses(t:Type, optional:Bool, useIdPrefix:String):Void {
				final targetType = ocamlTypeExprFromHaxeType(t);
				switch (targetType) {
					case OcamlTypeExpr.TIdent("bool"):
						addConstructorRuntimeUse(useIdPrefix + ":unbox-bool", "HxRuntime.unbox_bool_or_obj",
							OcamlRuntimeRequirementLedger.TYPE_REGISTRY_RUNTIME_UNBOX);
					case _:
				}
				addConstructorRuntimeUse(useIdPrefix + ":array-get", "HxArray.get", OcamlRuntimeRequirementLedger.TYPE_REGISTRY_DYNAMIC_ARGS);
				if (!optional)
					return;
				switch (targetType) {
					case OcamlTypeExpr.TIdent("Obj.t"):
						addConstructorRuntimeUse(useIdPrefix + ":dynamic-null", "HxRuntime.hx_null", OcamlRuntimeRequirementLedger.TYPE_REGISTRY_OPTIONAL_NULL);
					case OcamlTypeExpr.TIdent("string") if (OcamlRepresentationRegistry.isExactString(t)):
						addConstructorRuntimeUse(useIdPrefix + ":string-null", "HxString.hx_null_string",
							OcamlRuntimeRequirementLedger.TYPE_REGISTRY_OPTIONAL_STRING_NULL);
					case _:
						addConstructorRuntimeUse(useIdPrefix + ":boxed-null", "HxRuntime.hx_null", OcamlRuntimeRequirementLedger.TYPE_REGISTRY_OPTIONAL_NULL);
				}
			}
			for (name in enumNames) {
				final layouts = ctx.enumConstructorLayoutsByFullName.get(name);
				final moduleId = ctx.enumModuleIdByFullName.get(name);
				if (layouts == null || moduleId == null)
					continue;
				final moduleName = moduleIdToOcamlModuleName(moduleId);
				for (layout in layouts) {
					final useIdPrefix = "constructor:enum:" + name + ":" + layout.name;
					programIdentifiers.push({id: useIdPrefix + ":program-module", exactIdentifier: moduleName});
					programIdentifiers.push({id: useIdPrefix + ":program-constructor", exactIdentifier: layout.name});
					addConstructorRuntimeUse(useIdPrefix + ":register", "HxType.register_enum_ctor", OcamlRuntimeRequirementLedger.TYPE_REGISTRY);
					addConstructorRuntimeUse(useIdPrefix + ":array-type", "HxArray.t", OcamlRuntimeRequirementLedger.TYPE_REGISTRY_DYNAMIC_ARGS);
					final expected = ctx.enumCtorArgsByFullNameAndCtor.get(name + ":" + layout.name);
					final argsInfo = expected != null ? expected : [];
					if (argsInfo.length > 0) {
						addConstructorRuntimeUse(useIdPrefix + ":array-length", "HxArray.length", OcamlRuntimeRequirementLedger.TYPE_REGISTRY_DYNAMIC_ARGS);
						for (index in 0...argsInfo.length)
							planConstructorArgumentRuntimeUses(argsInfo[index].t, argsInfo[index].opt, useIdPrefix + ":argument:" + Std.string(index));
					}
				}
			}
			for (name in classNames) {
				final hasCtor = ctx.ctorPresentByFullName.exists(name) && ctx.ctorPresentByFullName.get(name) == true;
				final moduleId = ctx.classModuleIdByFullName.get(name);
				final parts = name.split(".");
				if (!hasCtor || moduleId == null || parts.length == 0)
					continue;
				final useIdPrefix = "constructor:class:" + name;
				programIdentifiers.push({id: useIdPrefix + ":program-module", exactIdentifier: moduleIdToOcamlModuleName(moduleId)});
				programIdentifiers.push({
					id: useIdPrefix + ":program-constructor",
					exactIdentifier: ctx.scopedValueName(moduleId, parts[parts.length - 1], "create")
				});
				addConstructorRuntimeUse(useIdPrefix + ":register", "HxType.register_class_ctor", OcamlRuntimeRequirementLedger.TYPE_REGISTRY);
				addConstructorRuntimeUse(useIdPrefix + ":array-type", "HxArray.t", OcamlRuntimeRequirementLedger.TYPE_REGISTRY_DYNAMIC_ARGS);
				final ctorArgs = ctx.ctorArgsByFullName.get(name);
				final expected = ctorArgs != null ? ctorArgs : [];
				if (expected.length > 0) {
					addConstructorRuntimeUse(useIdPrefix + ":array-length", "HxArray.length", OcamlRuntimeRequirementLedger.TYPE_REGISTRY_DYNAMIC_ARGS);
					for (index in 0...expected.length)
						planConstructorArgumentRuntimeUses(expected[index].t, expected[index].opt, useIdPrefix + ":argument:" + Std.string(index));
				}
			}
			for (index in 0...emptyConstructors.length) {
				final constructor = emptyConstructors[index];
				programIdentifiers.push({id: "program:empty-constructor-module:" + Std.string(index), exactIdentifier: constructor.moduleName});
				programIdentifiers.push({id: "program:empty-constructor-function:" + Std.string(index), exactIdentifier: constructor.targetFunctionName});
			}
			for (name in dynamicStringifierNames) {
				final stringifier = ctx.dynamicStringifierByFullName.get(name);
				if (stringifier == null)
					continue;
				final useId = "legacy:dynamic-stringifier:" + name;
				programIdentifiers.push({id: useId + ":program-module", exactIdentifier: moduleIdToOcamlModuleName(stringifier.moduleId)});
				programIdentifiers.push({id: useId + ":program-method", exactIdentifier: stringifier.targetMethodName});
			}

			final typeRegistry = new OcamlTypeRegistryBaseEmitter(artifactProfile, revision.id, useLineDirectives, classNames, enumNames, enumLayouts,
				emptyConstructors, classFields, classSupers, classTags, programIdentifiers, constructorRuntimeUses);
			typeRegistry.emitHeader();

			function ocamlExprForDynArgToExpected(t:Type, objExpr:String, useIdPrefix:String):String {
				final ot = ocamlTypeExprFromHaxeType(t);
				return switch (ot) {
					case OcamlTypeExpr.TIdent("Obj.t"):
						objExpr;
					case OcamlTypeExpr.TIdent("bool"):
						usesRuntimeUnbox = true;
						typeRegistry.runtimeToken(useIdPrefix + ":unbox-bool", "HxRuntime.unbox_bool_or_obj")
						+ " ("
						+ objExpr
						+ ")";
					case OcamlTypeExpr.TIdent("int") | OcamlTypeExpr.TIdent("float") | OcamlTypeExpr.TIdent("string") | OcamlTypeExpr.TIdent("bytes") | OcamlTypeExpr.TIdent("char"):
						"Obj.obj ("
						+ objExpr
						+ ")";
					case _:
						"Obj.magic (" + objExpr + ")";
				}
			}

			function ocamlExprForMissingOptionalArg(t:Type, useIdPrefix:String):String {
				final ot = ocamlTypeExprFromHaxeType(t);
				return switch (ot) {
					case OcamlTypeExpr.TIdent("Obj.t"):
						usesOptionalNullPadding = true;
						typeRegistry.runtimeToken(useIdPrefix + ":dynamic-null", "HxRuntime.hx_null");
					case OcamlTypeExpr.TIdent("string") if (OcamlRepresentationRegistry.isExactString(t)):
						exactStringNullValue(OcamlRepresentationDomain.InternalValue);
						usesOptionalStringNullPadding = true;
						typeRegistry.runtimeToken(useIdPrefix + ":string-null", "HxString.hx_null_string");
					case _:
						usesOptionalNullPadding = true;
						"Obj.magic " + typeRegistry.runtimeToken(useIdPrefix + ":boxed-null", "HxRuntime.hx_null");
				}
			}

			if (classNames.length == 0 && enumNames.length == 0 && classTagNames.length == 0) {
				typeRegistry.emitClassAndEnumIdentities();
				typeRegistry.emitEnumLayouts();
				typeRegistry.emitEmptyConstructors();
				typeRegistry.emitClassFields();
				typeRegistry.emitClassSupers();
				typeRegistry.emitClassTags();
			} else {
				ctx.markRuntimeModule("HxType");
				ctx.recordRuntimeInfrastructure(OcamlRuntimeRequirementLedger.TYPE_REGISTRY);
				typeRegistry.emitClassAndEnumIdentities();
				typeRegistry.emitEnumLayouts();
				// `Type.createEnum` / `Type.createEnumIndex` constructor registry (M10).
				for (n in enumNames) {
					final layouts = ctx.enumConstructorLayoutsByFullName.get(n);
					if (layouts == null)
						continue;
					final modId = ctx.enumModuleIdByFullName.get(n);
					if (modId == null)
						continue;
					final modName = moduleIdToOcamlModuleName(modId);
					for (layout in layouts) {
						final ctorName = layout.name;
						final key = n + ":" + ctorName;
						final expected = ctx.enumCtorArgsByFullNameAndCtor.get(key);
						final argsInfo = expected != null ? expected : [];

						final argsName = argsInfo.length == 0 ? "_args" : "args";
						final useIdPrefix = "constructor:enum:" + n + ":" + ctorName;
						final registerConstructor = typeRegistry.runtimeToken(useIdPrefix + ":register", "HxType.register_enum_ctor");
						final dynamicArrayType = typeRegistry.runtimeToken(useIdPrefix + ":array-type", "HxArray.t");
						typeRegistry.addTemplate("  " + registerConstructor + " " + ocamlStringLiteral(n) + " " + ocamlStringLiteral(ctorName) + " (fun ("
							+ argsName + " : Obj.t " + dynamicArrayType + ") ->\n");
						usesDynamicArgArrays = true;
						if (argsInfo.length == 0) {
							final programModule = typeRegistry.programIdentifierToken(useIdPrefix + ":program-module", modName);
							final programConstructor = typeRegistry.programIdentifierToken(useIdPrefix + ":program-constructor", ctorName);
							typeRegistry.addTemplate("    Obj.repr (" + programModule + "." + programConstructor + ")\n");
						} else {
							final arrayLength = typeRegistry.runtimeToken(useIdPrefix + ":array-length", "HxArray.length");
							typeRegistry.addTemplate("    let len = " + arrayLength + " args in\n");
							for (i in 0...argsInfo.length) {
								final ea = argsInfo[i];
								final argUseIdPrefix = useIdPrefix + ":argument:" + Std.string(i);
								final arrayGet = typeRegistry.runtimeToken(argUseIdPrefix + ":array-get", "HxArray.get");
								final fetch = "(" + arrayGet + " args " + Std.string(i) + ")";
								final inBounds = ocamlExprForDynArgToExpected(ea.t, fetch, argUseIdPrefix);
								final outOfBounds = ea.opt ? ocamlExprForMissingOptionalArg(ea.t,
									argUseIdPrefix) : ("failwith "
										+ ocamlStringLiteral("Type.createEnum: missing ctor arg '" + ea.name + "' for " + n + "." + ctorName));
								typeRegistry.addTemplate("    let a" + Std.string(i) + " = if len > " + Std.string(i) + " then " + inBounds + " else "
									+ outOfBounds + " in\n");
							}
							final argList = [for (i in 0...argsInfo.length) ("a" + Std.string(i))];
							final programModule = typeRegistry.programIdentifierToken(useIdPrefix + ":program-module", modName);
							final programConstructor = typeRegistry.programIdentifierToken(useIdPrefix + ":program-constructor", ctorName);
							final ctorCall = argsInfo.length > 1 ? (programModule + "." + programConstructor + " (" + argList.join(", ") + ")") : (programModule
								+ "." + programConstructor + " " + argList[0]);
							typeRegistry.addTemplate("    Obj.repr (" + ctorCall + ")\n");
						}
						typeRegistry.addLiteral("  );\n");
					}
				}
				// `Type.createInstance` constructor registry.
				for (n in classNames) {
					final hasCtor = ctx.ctorPresentByFullName.exists(n) && ctx.ctorPresentByFullName.get(n) == true;
					if (!hasCtor)
						continue;
					final modId = ctx.classModuleIdByFullName.get(n);
					if (modId == null)
						continue;
					final parts = n.split(".");
					if (parts.length == 0)
						continue;
					final typeName = parts[parts.length - 1];
					final modName = moduleIdToOcamlModuleName(modId);
					final createName = ctx.scopedValueName(modId, typeName, "create");
					final ctorArgs = ctx.ctorArgsByFullName.get(n);
					final expected = ctorArgs != null ? ctorArgs : [];

					final argsName = expected.length == 0 ? "_args" : "args";
					final useIdPrefix = "constructor:class:" + n;
					final registerConstructor = typeRegistry.runtimeToken(useIdPrefix + ":register", "HxType.register_class_ctor");
					final dynamicArrayType = typeRegistry.runtimeToken(useIdPrefix + ":array-type", "HxArray.t");
					typeRegistry.addTemplate("  " + registerConstructor + " " + ocamlStringLiteral(n) + " (fun (" + argsName + " : Obj.t "
						+ dynamicArrayType + ") ->\n");
					usesDynamicArgArrays = true;
					if (expected.length == 0) {
						final programModule = typeRegistry.programIdentifierToken(useIdPrefix + ":program-module", modName);
						final programConstructor = typeRegistry.programIdentifierToken(useIdPrefix + ":program-constructor", createName);
						typeRegistry.addTemplate("    Obj.repr (" + programModule + "." + programConstructor + " ())\n");
					} else {
						final arrayLength = typeRegistry.runtimeToken(useIdPrefix + ":array-length", "HxArray.length");
						typeRegistry.addTemplate("    let len = " + arrayLength + " args in\n");
						for (i in 0...expected.length) {
							final ea = expected[i];
							final argUseIdPrefix = useIdPrefix + ":argument:" + Std.string(i);
							final arrayGet = typeRegistry.runtimeToken(argUseIdPrefix + ":array-get", "HxArray.get");
							final fetch = "(" + arrayGet + " args " + Std.string(i) + ")";
							final inBounds = ocamlExprForDynArgToExpected(ea.t, fetch, argUseIdPrefix);
							final outOfBounds = ea.opt ? ocamlExprForMissingOptionalArg(ea.t,
								argUseIdPrefix) : ("failwith " + ocamlStringLiteral("Type.createInstance: missing ctor arg '" + ea.name + "' for " + n));
							typeRegistry.addTemplate("    let a" + Std.string(i) + " = if len > " + Std.string(i) + " then " + inBounds + " else "
								+ outOfBounds + " in\n");
						}
						final argList = [for (i in 0...expected.length) ("a" + Std.string(i))];
						final programModule = typeRegistry.programIdentifierToken(useIdPrefix + ":program-module", modName);
						final programConstructor = typeRegistry.programIdentifierToken(useIdPrefix + ":program-constructor", createName);
						typeRegistry.addTemplate("    Obj.repr (" + programModule + "." + programConstructor + " " + argList.join(" ") + ")\n");
					}
					typeRegistry.addLiteral("  );\n");
				}
				typeRegistry.emitEmptyConstructors();
				typeRegistry.emitClassFields();
				for (name in dynamicStringifierNames) {
					final stringifier = ctx.dynamicStringifierByFullName.get(name);
					if (stringifier == null)
						continue;
					final moduleName = moduleIdToOcamlModuleName(stringifier.moduleId);
					final useId = "legacy:dynamic-stringifier:" + name;
					final registerStringifier = typeRegistry.legacyRuntimeToken(useId, "HxDynamic.register_class_stringifier");
					final programModule = typeRegistry.programIdentifierToken(useId + ":program-module", moduleName);
					final programMethod = typeRegistry.programIdentifierToken(useId + ":program-method", stringifier.targetMethodName);
					typeRegistry.addTemplate("  " + registerStringifier + " " + ocamlStringLiteral(name) + " (fun value -> " + programModule + "."
						+ programMethod + " (Obj.obj value) ());\n");
				}
				if (dynamicStringifierNames.length > 0) {
					ctx.markRuntimeModule("HxDynamic");
					ctx.recordRuntimeInfrastructure(OcamlRuntimeRequirementLedger.TYPE_REGISTRY_DYNAMIC_STRING);
				}
				typeRegistry.emitClassSupers();
				typeRegistry.emitClassTags();
				if (usesDynamicArgArrays) {
					ctx.markRuntimeModule("HxArray");
					ctx.recordRuntimeInfrastructure(OcamlRuntimeRequirementLedger.TYPE_REGISTRY_DYNAMIC_ARGS);
				}
				if (usesOptionalNullPadding) {
					ctx.markRuntimeModule("HxRuntime");
					ctx.recordRuntimeInfrastructure(OcamlRuntimeRequirementLedger.TYPE_REGISTRY_OPTIONAL_NULL);
				}
				if (usesOptionalStringNullPadding) {
					ctx.markRuntimeModule("HxString");
					ctx.recordRuntimeInfrastructure(OcamlRuntimeRequirementLedger.TYPE_REGISTRY_OPTIONAL_STRING_NULL);
				}
				if (usesRuntimeUnbox) {
					ctx.markRuntimeModule("HxRuntime");
					ctx.recordRuntimeInfrastructure(OcamlRuntimeRequirementLedger.TYPE_REGISTRY_RUNTIME_UNBOX);
				}
			}
			typeRegistry.emitFooter();
			final typeRegistryRecord = typeRegistry.seal();
			OcamlCheckedGeneratedText.verify(typeRegistryRecord);
			output.saveFile("HxTypeRegistry.ml", typeRegistryRecord.content);
			artifacts.record({
				path: "HxTypeRegistry.ml",
				kind: OcamlArtifactKind.TypeRegistrySource,
				owner: OcamlArtifactOwner.CompilerCore,
				sourceKind: OcamlArtifactSourceKind.Generated,
				sourcePath: null,
				license: "generated-output",
				profileEligibility: ["portable", "metal"],
				stability: OcamlArtifactStability.Stable,
				includeInSourceBundle: true
			});
		}

		#if macro
		if (profileEnabled) {
			final now = profileNowS();
			final msg = "reflaxe.ocaml: onOutputComplete after type registry dt=" + Std.string(Math.round(now - profileStartS)) + "s";
			Context.warning(msg, Context.currentPos());
			profileLogLine(msg);
		}
		#end

		final noDune = haxe.macro.Context.defined("ocaml_no_dune");
		final duneLayoutValue = haxe.macro.Context.definedValue("ocaml_dune_layout");
		nativeSourceDeclarationAuthority = OcamlSourceBundleAuthority.nativeDeclarationsDisabled();
		if (!noDune) {
			final resolvedMainModuleId = resolveMainModuleIdForDune();
			final duneLibsValue = haxe.macro.Context.definedValue("ocaml_dune_libraries");
			final duneLibs = duneLibsValue == null ? ["unix", "str", "threads", "dynlink"] : duneLibsValue.split(",")
				.map(s -> StringTools.trim(s))
				.filter(s -> s.length > 0);

			final pluginRunMainValue = haxe.macro.Context.definedValue("ocaml_plugin_run_main");
			final pluginRunsMain = haxe.macro.Context.defined("ocaml_plugin_run_main")
				&& (pluginRunMainValue == null || StringTools.trim(pluginRunMainValue) != "0");
			final pluginRegisterProviderValue = haxe.macro.Context.definedValue("ocaml_plugin_register_provider");
			var pluginRegisterPluginId:Null<String> = null;
			var pluginRegisterProviderType:Null<String> = null;
			if (pluginRegisterProviderValue != null && StringTools.trim(pluginRegisterProviderValue).length > 0) {
				final rawRegistration = StringTools.trim(pluginRegisterProviderValue);
				final separator = rawRegistration.indexOf(":");
				if (separator <= 0 || separator >= rawRegistration.length - 1) {
					haxe.macro.Context.error("invalid -D ocaml_plugin_register_provider; expected <pluginId>:<providerType>", haxe.macro.Context.currentPos());
				} else {
					pluginRegisterPluginId = StringTools.trim(rawRegistration.substr(0, separator));
					pluginRegisterProviderType = StringTools.trim(rawRegistration.substr(separator + 1));
				}
			}
			final pluginLoadMarker = haxe.macro.Context.definedValue("ocaml_plugin_load_marker");

			final exesValue = haxe.macro.Context.definedValue("ocaml_dune_exes");
			final executables = if (exesValue == null || StringTools.trim(exesValue).length == 0) {
				null;
			} else {
				final out:Array<{name:String, mainModuleId:Null<String>}> = [];
				for (entry in exesValue.split(",")) {
					final e = StringTools.trim(entry);
					if (e.length == 0)
						continue;
					final colon = e.indexOf(":");
					if (colon < 0) {
						// Name only; use the compilation main module if available.
						out.push({name: e, mainModuleId: resolvedMainModuleId});
					} else {
						final exe = StringTools.trim(e.substr(0, colon));
						final mod = StringTools.trim(e.substr(colon + 1));
						if (exe.length == 0)
							continue;
						final modId = mod.length == 0 ? resolvedMainModuleId : StringTools.replace(mod, ".", "_");
						out.push({name: exe, mainModuleId: modId});
					}
				}
				out.length > 0 ? out : null;
			}

			final duneProjectConfig:DuneProjectConfig = {
				projectName: DuneProjectEmitter.defaultProjectName(outDir),
				exeName: DuneProjectEmitter.defaultExeName(outDir),
				mainModuleId: resolvedMainModuleId,
				pluginMainModuleId: pluginRunsMain ? resolvedMainModuleId : null,
				pluginRegisterPluginId: pluginRegisterPluginId,
				pluginRegisterProviderType: pluginRegisterProviderType,
				pluginLoadMarker: pluginLoadMarker,
				duneLibraries: duneLibs,
				duneLayout: duneLayoutValue,
				executables: executables
			};
			final emitsPluginRegistration = duneLayoutValue != null
				&& StringTools.trim(duneLayoutValue).toLowerCase() == "plugin"
				&& pluginRegisterPluginId != null
				&& pluginRegisterProviderType != null;
			if (emitsPluginRegistration)
				ctx.recordRuntimeInfrastructure(OcamlRuntimeRequirementLedger.HXHX_BACKEND_PLUGIN_HOST);
			nativeSourceDeclarationAuthority = OcamlSourceBundleAuthority.nativeDeclarations(duneProjectConfig);
			final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
			DuneProjectEmitter.emit(output, duneProjectConfig, artifacts, revision.id, activeProfile, ctx.runtimeRequirementsSorted());
		}

		final noRuntime = haxe.macro.Context.defined("ocaml_no_runtime");
		semanticRuntimeAuthority = OcamlSourceBundleAuthority.semanticRuntimeDisabled();
		if (!noRuntime) {
			ctx.recordRuntimeInfrastructure(OcamlRuntimeRequirementLedger.CORE_RUNTIME);
			semanticRuntimeAuthority = RuntimeCopier.copy(output, artifacts, "runtime", ctx.runtimeModulesSorted(), ctx.emittedOcamlModuleNamesSorted(),
				ctx.runtimeRequirementsSorted(), ctx.runtimeRequirementRevision(), targetReuseRuntimeSourceManifest);
		}

		// OCaml-native (M12): emit functor-instantiated modules when requested by interop surfaces.
		if (ctx.needsOcamlNativeMapSet) {
			OcamlNativeFunctorEmitter.emitMapSet(output, artifacts);
		}

		// Package alias modules (M8): generate dot-path access helpers unless disabled.
		final emitAliasesValue = haxe.macro.Context.definedValue("ocaml_emit_package_aliases");
		final emitAliases = emitAliasesValue != null ? emitAliasesValue != "0" : !pluginModeEnabled;
		if (emitAliases) {
			final modules:Array<String> = [];
			for (m => _ in ctx.emittedHaxeModules)
				modules.push(m);
			PackageAliasEmitter.emit(output, modules, artifacts, (m) -> ctx.ocamlModuleNameForModuleId(m));
		}

		artifacts.recordFrameworkModules(excludedFrameworkPaths);

		if (emitExcludePathPrefixes.length > 0) {
			final outputFiles:Array<String> = [];
			collectOutputFilesRecursive(outDir, "", outputFiles);
			for (relPath in outputFiles) {
				if (!shouldExcludeOutputPath(relPath))
					continue;
				if (relPath == OcamlArtifactManifestSchema.FRAMEWORK_RECEIPT) {
					haxe.macro.Context.error("ocaml_emit_exclude_paths cannot remove Reflaxe's generated-file receipt; choose a source-module prefix instead.",
						haxe.macro.Context.currentPos());
				}
				if (!artifacts.isRecorded(relPath))
					continue;
				final absPath = haxe.io.Path.join([outDir, relPath]);
				if (sys.FileSystem.exists(absPath) && !sys.FileSystem.isDirectory(absPath)) {
					sys.FileSystem.deleteFile(absPath);
					artifacts.discardRecorded(relPath);
				}
			}
			pruneEmptyDirectoriesRecursive(outDir);
		}

		#if macro
		final snapshot = finalProgramFingerprint;
		final probe = targetReuseProbe;
		if (probe != null && probe.eligible) {
			final runtimeAuthority = semanticRuntimeAuthority;
			final nativeAuthority = nativeSourceDeclarationAuthority;
			if (snapshot == null || probe == null || probe.requestRevision == null)
				throw "reflaxe.ocaml: target source packing requires a sealed final-program probe";
			if (runtimeAuthority == null || nativeAuthority == null)
				throw "reflaxe.ocaml: target source packing requires complete source authority";
			final sourceSnapshot = artifacts.snapshotSourceBundle(runtimeAuthority, nativeAuthority);
			final diagnosticsEligible = probe.eligible && skippedTargetGenerationWarnings == 0;
			var candidate:Null<OcamlSourceBundleCandidate> = null;
			switch (OcamlSourceBundleCandidate.tryPack(outDir, probe.requestRevision, sourceSnapshot, diagnosticsEligible)) {
				case Packed(packed):
					candidate = packed;
				case EntryBudgetExceeded(_, _):
					TargetReuseCatalog.shared().recordMiss("entry-budget-exceeded");
			}
			if (probe.eligible && candidate != null)
				if (diagnosticsEligible)
					stagedTargetReuseCandidate = candidate;
				else
					TargetReuseCatalog.shared().recordMiss("target-generation-diagnostics");
			OcamlTargetReuseTestHooks.failAfterStage();
		}
		#end

		final buildMode = haxe.macro.Context.definedValue("ocaml_build");
		final shouldRun = haxe.macro.Context.defined("ocaml_run");
		final noBuild = haxe.macro.Context.defined("ocaml_no_build");
		final emitOnly = haxe.macro.Context.defined("ocaml_emit_only");

		final mliValue = haxe.macro.Context.definedValue("ocaml_mli");
		final wantsMli = haxe.macro.Context.defined("ocaml_mli") || mliValue != null;
		final mliMode = if (!wantsMli) {
			null;
		} else if (mliValue == null || mliValue.length == 0 || mliValue == "1") {
			"infer";
		} else {
			mliValue;
		}
		final mliBestEffort = haxe.macro.Context.defined("ocaml_mli_best_effort");
		final mliStrict = wantsMli && !mliBestEffort;

		if (wantsMli && (noBuild || emitOnly)) {
			haxe.macro.Context.warning("ocaml_mli implies a dune build/typecheck step; ignoring ocaml_no_build/ocaml_emit_only.",
				haxe.macro.Context.currentPos());
		}
		if (wantsMli && noDune) {
			haxe.macro.Context.error("ocaml_mli requires dune scaffolding (or a dune project in the output dir). Disable ocaml_no_dune.",
				haxe.macro.Context.currentPos());
		}

		final shouldBuild = wantsMli || (!noBuild && !emitOnly);
		final strictBuild = buildMode != null;
		final strictAny = strictBuild || (wantsMli && mliStrict);

		if (!shouldBuild && !shouldRun) {
			sealArtifactManifest(artifacts);
			return;
		}

		final exeName = DuneProjectEmitter.defaultExeName(outDir);
		final mode = buildMode != null ? buildMode : "native";
		final publicOutDir = output.publicOutputDir;
		final transactionalOutput = publicOutDir != null && Path.normalize(publicOutDir) != Path.normalize(outDir);
		if (transactionalOutput) {
			if (wantsMli) {
				throw "reflaxe.ocaml: transactional ocaml_mli passed the pre-generation configuration boundary";
			}
			final stablePublicOutDir:String = cast publicOutDir;
			sealArtifactManifest(artifacts);
			pendingPublishedOutputBuild = {
				publicDirectory: stablePublicOutDir,
				buildDirectory: OcamlDuneBuildState.forOutputDirectory(stablePublicOutDir),
				exeName: DuneProjectEmitter.defaultExeName(stablePublicOutDir),
				mode: mode,
				duneLayout: duneLayoutValue,
				run: shouldRun,
				strict: strictAny,
				timingReport: haxe.macro.Context.defined("ocaml_build_timing_report"),
				artifacts: artifacts
			};
			return;
		}

		final result = OcamlBuildRunner.tryBuildAndMaybeRun({
			outDir: outDir,
			buildDir: null,
			exeName: exeName,
			mode: mode,
			duneLayout: duneLayoutValue,
			run: shouldRun,
			strict: strictAny,
			mli: mliMode,
			mliStrict: mliStrict,
			timingReport: haxe.macro.Context.defined("ocaml_build_timing_report"),
			artifacts: artifacts
		});

		switch (result) {
			case Ok(msg):
				if (msg != null)
					haxe.macro.Context.warning(msg, haxe.macro.Context.currentPos());
			case Err(msg):
				// Strict mode (ocaml_build=...) should stop compilation if build fails.
				haxe.macro.Context.error(msg, haxe.macro.Context.currentPos());
		}
		sealArtifactManifest(artifacts);
		#if macro
		if (profileEnabled) {
			final now = profileNowS();
			final msg = "reflaxe.ocaml: onOutputComplete end dt=" + Std.string(Math.round(now - profileStartS)) + "s";
			Context.warning(msg, Context.currentPos());
			profileLogLine(msg);
		}
		#end
		#end
	}

	public function compileEnumImpl(enumType:EnumType, options:Array<EnumOptionData>):Null<String> {
		#if macro
		profEnumCount++;
		final profEnumName = (enumType.pack ?? []).concat([enumType.name]).join(".");
		profileWarnEvery("enum", profEnumCount, profEnumName, enumType.pos, 50);
		if (profileVerbose)
			profileLogLine("reflaxe.ocaml: enum_begin count=" + Std.string(profEnumCount) + " name=" + profEnumName);
		#end
		// ocaml.* surface types map to native Stdlib types; do not emit duplicate type decls
		// and do not register reflection metadata for modules that won't exist.
		if (enumType.pack != null && enumType.pack.length == 1 && enumType.pack[0] == "ocaml") {
			switch (enumType.name) {
				case "List", "Option", "Result":
					return null;
				case _:
			}
		}

		ctx.emittedHaxeModules.set(enumType.module, true);
		ctx.currentModuleId = enumType.module;
		final moduleFileId = ctx.fileIdForModuleId(enumType.module);
		if (ctx.fileIdOverrideByModuleId.exists(enumType.module) || ctx.modulePrefix != null) {
			setOutputFileName(moduleFileId);
		}
		final fullName = (enumType.pack ?? []).concat([enumType.name]).join(".");
		#if macro
		ctx.currentIsHaxeStd = isPosInHaxeStd(enumType.pos);
		final runtimeName = {
			final n = extractNativeString(enumType.meta);
			n != null ? n : fullName;
		};
		if (!ctx.currentIsHaxeStd || haxe.macro.Context.defined("reflaxe_ocaml_full_type_registry")) {
			ctx.nonStdTypeRegistryEnums.set(runtimeName, true);
		}
		ctx.enumModuleIdByFullName.set(runtimeName, enumType.module);
		// Haxe declaration indices and native OCaml tags are different number
		// spaces. Record both while the typed enum declaration is available so
		// Dynamic reflection never has to infer source order from runtime layout.
		{
			var immediateTag = 0;
			var blockTag = 0;
			final layouts:Array<OcamlEnumConstructorLayout> = [];
			for (option in options) {
				final native = extractNativeString(option.field.meta);
				final carriesPayload = option.args.length > 0;
				final ocamlTag = if (carriesPayload) blockTag++ else immediateTag++;
				layouts.push({
					name: native != null ? native : option.name,
					haxeIndex: option.field.index,
					carriesPayload: carriesPayload,
					ocamlTag: ocamlTag
				});
			}
			layouts.sort((left, right) -> left.haxeIndex - right.haxeIndex);
			ctx.enumConstructorLayoutsByFullName.set(runtimeName, layouts);
		}
		// Enum constructor signatures for `Type.createEnum` / `Type.createEnumIndex` (M10).
		{
			for (opt in options) {
				final ctorName = {
					final n = extractNativeString(opt.field.meta);
					n != null ? n : opt.name;
				};
				final args:Null<Array<{name:String, opt:Bool, t:Type}>> = switch (TypeTools.follow(opt.field.type)) {
					case TFun(fargs, _): fargs;
					case _: null;
				};
				ctx.enumCtorArgsByFullNameAndCtor.set(runtimeName + ":" + ctorName, args != null ? args : []);
			}
		}
		#end

		final typeName = ocamlTypeName(enumType.name);
		final typeParams = enumType.params.map(p -> ocamlTypeParam(p.name));

		final ctors:Array<OcamlVariantConstructor> = [];
		for (opt in options) {
			final args:Array<OcamlTypeExpr> = [];
			for (a in opt.args) {
				var argType = ocamlTypeExprFromHaxeType(a.type);
				if (a.opt) {
					// Haxe optional enum-constructor arguments (`?x:T`) behave like `Null<T>`.
					//
					// For most OCaml representations we can keep the underlying type and rely on
					// the `HxRuntime.hx_null` sentinel (cast via `Obj.magic`) at callsites.
					//
					// However, for primitives (Int/Float/Bool) we cannot safely represent a null
					// sentinel *as a primitive*, so we use the nullable-primitive representation:
					// `Obj.t` with `HxRuntime.hx_null` for null and `Obj.repr <prim>` for non-null.
					argType = switch (TypeTools.follow(a.type)) {
						case TAbstract(aRef, _):
							final abs = aRef.get();
							(abs.name == "Int" || abs.name == "Float" || abs.name == "Bool") ? OcamlTypeExpr.TIdent("Obj.t") : argType;
						case _:
							argType;
					}
				}
				args.push(argType);
			}
			ctors.push({name: opt.name, args: args});
		}

		final decl:OcamlTypeDecl = {
			name: typeName,
			params: typeParams,
			kind: OcamlTypeDeclKind.Variant(ctors)
		};

		final items:Array<OcamlModuleItem> = [OcamlModuleItem.IType([decl], false)];
		RuntimeUsageCollector.collectFromModuleItems(items, (moduleName) -> ctx.markRuntimeModule(moduleName));

		var out = "(* Generated by reflaxe.ocaml (WIP) *)\n(* Haxe enum: " + fullName + " *)\n\n";
		out += printer.printModule(items);
		return out;
	}

	public function compileExpressionImpl(expr:TypedExpr, topLevel:Bool):Null<String> {
		#if macro
		final sourceMapValue = haxe.macro.Context.definedValue("ocaml_sourcemap");
		final emitSourceMap = haxe.macro.Context.defined("ocaml_sourcemap")
			&& (sourceMapValue == null || sourceMapValue.length == 0 || sourceMapValue == "1" || sourceMapValue == "directives");
		#else
		final emitSourceMap = false;
		#end
		final builder = new OcamlBuilder(ctx, ocamlTypeExprFromHaxeType, functionPlanRegistry, representationRegistry, staticStoragePlan, emitSourceMap);
		final e = buildStandaloneExpression(builder, compilerExpressionOwner(expr), expr);
		return printer.printExpr(e);
	}

	function compileConstant(c:TConstant):Null<String> {
		return switch (c) {
			case TInt(i): Std.string(i);
			case TFloat(f): Std.string(f);
			case TString(s): "\"" + escapeOcamlString(s) + "\"";
			case TBool(b): b ? "true" : "false";
			case TNull: "()"; // placeholder
			case TThis: "self"; // placeholder
			case TSuper: "super"; // placeholder
		}
	}

	static function escapeOcamlString(s:String):String {
		// Minimal escaping for scaffold output; printer milestone will replace.
		return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t");
	}

	static function ocamlTypeName(haxeName:String):String {
		if (haxeName == null || haxeName.length == 0)
			return "t";
		final first = haxeName.charCodeAt(0);
		final isUpper = first >= 65 && first <= 90;
		var s = (isUpper ? String.fromCharCode(first + 32) : haxeName.substr(0, 1)) + haxeName.substr(1);
		s = sanitizeLowerIdent(s);
		if (s.length == 0)
			return "t";
		// OCaml keywords are not valid identifiers in type declarations (`type type = ...` is a syntax error).
		// Keep emission deterministic by prefixing reserved names.
		return OcamlNameTools.isOcamlReservedValueName(s) ? ("hx_" + s) : s;
	}

	static function ocamlTypeParam(haxeName:String):String {
		if (haxeName == null || haxeName.length == 0)
			return "a";
		final s = sanitizeLowerIdent(haxeName.toLowerCase());
		if (s.length == 0)
			return "a";
		return OcamlNameTools.isOcamlReservedValueName(s) ? ("hx_" + s) : s;
	}

	static function sanitizeLowerIdent(name:String):String {
		final out = new StringBuf();
		for (i in 0...name.length) {
			final c = name.charCodeAt(i);
			final isAlphaNum = (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57);
			out.add(isAlphaNum ? String.fromCharCode(c).toLowerCase() : "_");
		}
		var s = out.toString();
		if (s.length == 0)
			return s;
		final first = s.charCodeAt(0);
		if (first >= 48 && first <= 57)
			s = "_" + s;
		return s;
	}

	inline function moduleIdToOcamlModuleName(moduleId:String):String {
		return ctx.ocamlModuleNameForModuleId(moduleId);
	}

	static function extractNativeString(meta:Null<MetaAccess>):Null<String> {
		#if macro
		if (meta == null)
			return null;
		for (m in meta.get()) {
			if (m.name != ":native")
				continue;
			if (m.params == null || m.params.length == 0)
				continue;
			return switch (m.params[0].expr) {
				case EConst(CString(s)): s;
				case _: null;
			}
		}
		#end
		return null;
	}

	function ocamlTypeExprFromHaxeType(t:Type):OcamlTypeExpr {
		return switch (t) {
			case TAbstract(aRef, params):
				final a = aRef.get();
				final aPack = a.pack ?? [];

				if (OcamlRepresentationRegistry.isExactBytesData(t))
					return OcamlTypeExpr.TIdent("bytes");

				// OCaml-native surface: treat `ocaml.*` abstracts as concrete OCaml types so they can
				// appear in generated type annotations (records, signatures, future .mli output)
				// without degrading to `Obj.t`.
				if (aPack.length == 1 && aPack[0] == "ocaml") {
					switch (a.name) {
						case "Array":
							final elem = (params != null && params.length > 0) ? ocamlTypeExprFromHaxeType(params[0]) : OcamlTypeExpr.TIdent("Obj.t");
							return OcamlTypeExpr.TApp("array", [elem]);
						case "StringMap":
							final v = (params != null && params.length > 0) ? ocamlTypeExprFromHaxeType(params[0]) : OcamlTypeExpr.TIdent("Obj.t");
							return OcamlTypeExpr.TApp("OcamlNativeStringMap.t", [v]);
						case "IntMap":
							final v = (params != null && params.length > 0) ? ocamlTypeExprFromHaxeType(params[0]) : OcamlTypeExpr.TIdent("Obj.t");
							return OcamlTypeExpr.TApp("OcamlNativeIntMap.t", [v]);
						case "StringSet":
							return OcamlTypeExpr.TIdent("OcamlNativeStringSet.t");
						case "IntSet":
							return OcamlTypeExpr.TIdent("OcamlNativeIntSet.t");
						case "Bytes":
							return OcamlTypeExpr.TIdent("bytes");
						case "Char":
							return OcamlTypeExpr.TIdent("char");
						case "Buffer":
							return OcamlTypeExpr.TIdent("Stdlib.Buffer.t");
						case "Hashtbl":
							final k = (params != null && params.length > 0) ? ocamlTypeExprFromHaxeType(params[0]) : OcamlTypeExpr.TIdent("Obj.t");
							final v = (params != null && params.length > 1) ? ocamlTypeExprFromHaxeType(params[1]) : OcamlTypeExpr.TIdent("Obj.t");
							return OcamlTypeExpr.TApp("Stdlib.Hashtbl.t", [k, v]);
						case "Seq":
							final elem = (params != null && params.length > 0) ? ocamlTypeExprFromHaxeType(params[0]) : OcamlTypeExpr.TIdent("Obj.t");
							return OcamlTypeExpr.TApp("Stdlib.Seq.t", [elem]);
						case _:
					}
				} else if (aPack.length == 2 && aPack[0] == "ocaml" && aPack[1] == "extlib" && a.name == "PMap") {
					final k = (params != null && params.length > 0) ? ocamlTypeExprFromHaxeType(params[0]) : OcamlTypeExpr.TIdent("Obj.t");
					final v = (params != null && params.length > 1) ? ocamlTypeExprFromHaxeType(params[1]) : OcamlTypeExpr.TIdent("Obj.t");
					return OcamlTypeExpr.TApp("PMap.t", [k, v]);
				}
				// haxe.Int32 is a 32-bit-int abstract over `Int`. Our backend already enforces
				// 32-bit overflow semantics for `Int` via `HxInt`, so we represent Int32 as
				// a plain OCaml `int`.
				if (aPack.length == 1 && aPack[0] == "haxe" && a.name == "Int32") {
					return OcamlTypeExpr.TIdent("int");
				}
				// haxe.Int64 is an abstract over an internal record class (`haxe._Int64.___Int64`).
				// Represent it as that concrete record type so consumers can access `high/low`
				// without falling back to `Obj.t`.
				if (aPack.length == 1 && aPack[0] == "haxe" && a.name == "Int64") {
					return OcamlTypeExpr.TIdent("Haxe_Int64.___int64_t");
				}
				// haxe.Ucs2 is an abstract over String and should stay string-typed in OCaml.
				// This keeps helper calls like `toNativeString()` and direct comparisons typed.
				if (aPack.length == 1 && aPack[0] == "haxe" && a.name == "Ucs2") {
					return OcamlTypeExpr.TIdent("string");
				}
				// haxe.extern.AsVar<T> is an extern typing helper and should erase to `T`.
				if (aPack.length == 2 && aPack[0] == "haxe" && aPack[1] == "extern" && a.name == "AsVar" && params != null && params.length == 1) {
					return ocamlTypeExprFromHaxeType(params[0]);
				}
				// String-backed abstracts should keep `string` typing in OCaml.
				// Falling back to `Obj.t` for these wrappers causes mismatches at string callsites.
				if (switch (TypeTools.follow(a.type)) {
						case TInst(cRef, _): final c = cRef.get(); c.pack != null && c.pack.length == 0 && c.name == "String";
						case _: false;
					}) {
					return OcamlTypeExpr.TIdent("string");
					}
				#if macro
				// Enum abstracts (`@:enum abstract X(Int)`) should keep their underlying primitive
				// representation in OCaml. Falling back to `Obj.t` breaks comparisons and pattern
				// matches in modules like `Xml` / `haxe.xml.Parser` / `haxe.xml.Printer`.
				if (a.meta != null && a.meta.has(":enum")) {
					return ocamlTypeExprFromHaxeType(a.type);
				}
				#end
				// haxe.ds.Map is an abstract over `haxe.Constraints.IMap` with specialization
				// for common key types (String/Int) and a fallback to ObjectMap.
				//
				// If we default this to `Obj.t`, we end up forcing top-level `ref` annotations
				// (`ref (HxMap.create_string () : Obj.t)`) which breaks compilation because the
				// concrete map implementation is not boxed.
				//
				// Represent it as its concrete OCaml runtime map type based on the key kind.
				if (aPack.length == 2 && aPack[0] == "haxe" && aPack[1] == "ds" && a.name == "Map") {
					final k = (params != null && params.length > 0) ? params[0] : null;
					final v = (params != null && params.length > 1) ? params[1] : null;
					final vT = v != null ? ocamlTypeExprFromHaxeType(v) : OcamlTypeExpr.TIdent("Obj.t");

					// Follow key abstracts so `Map<Int, V>` (where Int is an abstract) is detected.
					final kFollowed = k != null ? TypeTools.follow(k) : null;
					switch (kFollowed) {
						case TInst(cRef, _):
							final c = cRef.get();
							if (c.pack != null && c.pack.length == 0 && c.name == "String") {
								return OcamlTypeExpr.TApp("HxMap.string_map", [vT]);
							}
							// Non-String class keys use ObjectMap.
							final kT = ocamlTypeExprFromHaxeType(kFollowed);
							return OcamlTypeExpr.TApp("HxMap.obj_map", [kT, vT]);
						case TAbstract(kRef, _):
							final ka = kRef.get();
							if (ka.name == "Int") {
								return OcamlTypeExpr.TApp("HxMap.int_map", [vT]);
							}
							// Unknown abstract keys: treat as ObjectMap.
							final kT = ocamlTypeExprFromHaxeType(kFollowed);
							return OcamlTypeExpr.TApp("HxMap.obj_map", [kT, vT]);
						case _:
							// Default to ObjectMap for any other key type.
							final kT = kFollowed != null ? ocamlTypeExprFromHaxeType(kFollowed) : OcamlTypeExpr.TIdent("Obj.t");
							return OcamlTypeExpr.TApp("HxMap.obj_map", [kT, vT]);
					}
				}
				switch (a.name) {
					case "Int": OcamlTypeExpr.TIdent("int");
					case "Float": OcamlTypeExpr.TIdent("float");
					case "Bool": OcamlTypeExpr.TIdent("bool");
					case "Void": OcamlTypeExpr.TIdent("unit");
					case "CallStack":
						// `haxe.CallStack` is an abstract over `Array<haxe.StackItem>`.
						// For OCaml output, represent it as its underlying array type so functions like
						// `haxe.CallStack.toString` can accept it without `Obj.magic` gymnastics.
						ocamlTypeExprFromHaxeType(a.type);
					case "Null":
						// `Null<T>` uses the backend's nullable representation for `T`.
						//
						// - `Null<Int/Float/Bool>` => `Obj.t` (uses `HxRuntime.hx_null` sentinel).
						// - `Null<String>` => `string` (uses the runtime-owned `HxString.hx_null_string` sentinel).
						// - `Null<Enum>` => `Obj.t` (enums are variants; we avoid `Obj.magic` sentinels).
						// - `Null<Class>` => the underlying record type (uses `Obj.magic` sentinel).
						if (params != null && params.length == 1) {
							switch (TypeTools.follow(params[0])) {
								case TAbstract(innerRef, _):
									final inner = innerRef.get();
									(inner.name == "Int" || inner.name == "Float" || inner.name == "Bool") ? OcamlTypeExpr.TIdent("Obj.t") : (inner.name == "CallStack" ? ocamlTypeExprFromHaxeType(innerRef.get()
										.type) : OcamlTypeExpr.TIdent("Obj.t"));
								case TInst(cRef, innerParams):
									final c = cRef.get();
									final mapCarrier = OcamlStandardMapCarrierContract.carrierForClass(c, innerParams, ocamlTypeExprFromHaxeType);
									switch (c.kind) {
										case KTypeParameter(_):
											// Portable mode doesn't model polymorphic class parameters in OCaml.
											// Treat them as an opaque runtime value type.
											return OcamlTypeExpr.TIdent("Obj.t");
										case _:
									}
									if (c.pack != null && c.pack.length == 0 && c.name == "String") {
										OcamlTypeExpr.TIdent("string");
									} else if (c.pack != null && c.pack.length == 0 && c.name == "Array") {
										final elem = innerParams.length > 0 ? ocamlTypeExprFromHaxeType(innerParams[0]) : OcamlTypeExpr.TIdent("Obj.t");
										OcamlTypeExpr.TApp("HxArray.t", [elem]);
									} else if (mapCarrier != null) {
										mapCarrier;
									} else if (c.pack != null && c.pack.length == 2 && c.pack[0] == "haxe" && c.pack[1] == "io" && c.name == "Bytes") {
										OcamlTypeExpr.TIdent("HxBytes.t");
									} else if (c.isExtern) {
										OcamlTypeExpr.TIdent("Obj.t");
									} else {
										final modName = moduleIdToOcamlModuleName(c.module);
										final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
										final scoped = ctx.scopedInstanceTypeName(c.module, c.name);
										final full = (selfMod != null && selfMod == modName) ? scoped : (modName + "." + scoped);
										OcamlTypeExpr.TIdent(full);
									}
								case TEnum(_, _):
									OcamlTypeExpr.TIdent("Obj.t");
								case _:
									OcamlTypeExpr.TIdent("Obj.t");
							}
						} else {
							OcamlTypeExpr.TIdent("Obj.t");
						}
					default:
						final followed = TypeTools.follow(a.type);
						switch (followed) {
							case TAbstract(innerRef, _):
								final inner = innerRef.get();
								final samePack = (inner.pack ?? []).join(".") == aPack.join(".");
								(samePack && inner.name == a.name) ? OcamlTypeExpr.TIdent("Obj.t") : ocamlTypeExprFromHaxeType(followed);
							case _:
								ocamlTypeExprFromHaxeType(followed);
						}
				}
			case TInst(cRef, params):
				final c = cRef.get();
				final mapCarrier = OcamlStandardMapCarrierContract.carrierForClass(c, params, ocamlTypeExprFromHaxeType);
				switch (c.kind) {
					case KTypeParameter(_):
						// Portable mode doesn't model polymorphic class parameters in OCaml.
						// Treat them as an opaque runtime value type.
						return OcamlTypeExpr.TIdent("Obj.t");
					case _:
				}
				if (c.pack != null && c.pack.length == 0 && c.name == "String") {
					OcamlTypeExpr.TIdent("string");
				} else if (c.pack != null && c.pack.length == 0 && c.name == "Array") {
					// Haxe Array<T> -> 't HxArray.t (runtime is permissive; type is best-effort).
					final elem = params.length > 0 ? ocamlTypeExprFromHaxeType(params[0]) : OcamlTypeExpr.TIdent("Obj.t");
					OcamlTypeExpr.TApp("HxArray.t", [elem]);
				} else if (mapCarrier != null) {
					mapCarrier;
				} else if (OcamlStandardIMapCallContract.isIMapClass(c) && params.length == 2) {
					// An `IMap` value carries a checked dispatch record, not key-selected
					// standard Map storage. The record itself is boxed so standard maps and
					// user implementations share one interface type without claiming the
					// same runtime object layout.
					OcamlTypeExpr.TIdent("Obj.t");
				} else if (c.pack != null && c.pack.length == 2 && c.pack[0] == "haxe" && c.pack[1] == "io" && c.name == "Bytes") {
					OcamlTypeExpr.TIdent("HxBytes.t");
				} else if (c.pack != null && c.pack.length == 1 && c.pack[0] == "ocaml" && c.name == "Ref") {
					final elem = params.length > 0 ? ocamlTypeExprFromHaxeType(params[0]) : OcamlTypeExpr.TIdent("Obj.t");
					OcamlTypeExpr.TApp("ref", [elem]);
				} else if (c.isExtern) {
					OcamlTypeExpr.TIdent("Obj.t");
				} else {
					// User class instances are represented by the module's `t` type.
					final modName = moduleIdToOcamlModuleName(c.module);
					final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
					final scoped = ctx.scopedInstanceTypeName(c.module, c.name);
					final full = (selfMod != null && selfMod == modName) ? scoped : (modName + "." + scoped);
					OcamlTypeExpr.TIdent(full);
				}
			case TEnum(eRef, params):
				final e = eRef.get();
				final ePack = e.pack ?? [];

				// OCaml-native surface: map `ocaml.List/Option/Result` types to Stdlib types.
				// (We still special-case constructors/patterns separately in the builder.)
				if (ePack.length == 1 && ePack[0] == "ocaml") {
					switch (e.name) {
						case "List":
							final elem = params.length > 0 ? ocamlTypeExprFromHaxeType(params[0]) : OcamlTypeExpr.TIdent("Obj.t");
							return OcamlTypeExpr.TApp("list", [elem]);
						case "Option":
							final elem = params.length > 0 ? ocamlTypeExprFromHaxeType(params[0]) : OcamlTypeExpr.TIdent("Obj.t");
							return OcamlTypeExpr.TApp("option", [elem]);
						case "Result":
							final okT = params.length > 0 ? ocamlTypeExprFromHaxeType(params[0]) : OcamlTypeExpr.TIdent("Obj.t");
							final errT = params.length > 1 ? ocamlTypeExprFromHaxeType(params[1]) : OcamlTypeExpr.TIdent("Obj.t");
							return OcamlTypeExpr.TApp("result", [okT, errT]);
						case _:
					}
				}
				final modName = moduleIdToOcamlModuleName(e.module);
				final selfMod = ctx.currentModuleId == null ? null : moduleIdToOcamlModuleName(ctx.currentModuleId);
				final typeName = ocamlTypeName(e.name);
				final full = (selfMod != null && selfMod == modName) ? typeName : (modName + "." + typeName);
				params.length == 0 ? OcamlTypeExpr.TIdent(full) : OcamlTypeExpr.TApp(full, params.map(ocamlTypeExprFromHaxeType));
			case TType(tRef, params):
				final td = tRef.get();
				final applied = TypeTools.applyTypeParameters(td.type, td.params, params);
				ocamlTypeExprFromHaxeType(applied);
			case TDynamic(_), TAnonymous(_), TMono(_), TLazy(_):
				OcamlTypeExpr.TIdent("Obj.t");
			case TFun(args, ret):
				final retT = isVoidType(ret) ? OcamlTypeExpr.TIdent("unit") : ocamlTypeExprFromHaxeType(ret);
				final argTs = args.map(a -> ocamlTypeExprFromHaxeType(a.t));
				// Haxe 0-arg functions still receive a `()` application at many callsites in this backend
				// (to avoid accidental partial application). Model them as `unit -> ret`.
				var acc = retT;
				if (argTs.length == 0) {
					acc = OcamlTypeExpr.TArrow(OcamlTypeExpr.TIdent("unit"), acc);
				} else {
					for (i in 0...argTs.length) {
						final from = argTs[argTs.length - 1 - i];
						acc = OcamlTypeExpr.TArrow(from, acc);
					}
				}
				acc;
		}
	}

	static inline function fullNameOfClassType(cls:ClassType):String {
		return (cls.pack ?? []).concat([cls.name]).join(".");
	}

	static function isVoidType(t:Type):Bool {
		return switch (TypeTools.follow(t)) {
			case TAbstract(aRef, _):
				final a = aRef.get();
				(a.pack ?? []).length == 0 && a.name == "Void";
			case _:
				false;
		}
	}

	static function funReturnsVoid(t:Type):Bool {
		return switch (t) {
			case TFun(_, ret): isVoidType(ret);
			case _: false;
		}
	}

	static function classTagsForClassType(cls:ClassType):Array<String> {
		final tags:Array<String> = [];
		final visited:Map<String, Bool> = [];

		inline function add(tag:String):Void {
			if (!visited.exists(tag)) {
				visited.set(tag, true);
				tags.push(tag);
			}
		}

		function addInterfaceTags(iface:ClassType):Void {
			final name = fullNameOfClassType(iface);
			if (visited.exists(name))
				return;
			add(name);
			for (i in iface.interfaces)
				addInterfaceTags(i.t.get());
		}

		function addClassTags(c:ClassType):Void {
			final name = fullNameOfClassType(c);
			if (visited.exists(name))
				return;
			add(name);
			for (i in c.interfaces)
				addInterfaceTags(i.t.get());
			if (c.superClass != null)
				addClassTags(c.superClass.t.get());
		}

		addClassTags(cls);
		return tags;
	}

	function defaultValueForType(t:Type):OcamlExpr {
		if (OcamlRepresentationRegistry.isExactString(t))
			return exactStringNullValue(OcamlRepresentationDomain.InternalValue);
		final anyNull:OcamlExpr = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.magic"), [OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")]);

		return switch (t) {
			case TAbstract(aRef, params):
				final a = aRef.get();
				switch (a.name) {
					case "Int": OcamlExpr.EConst(OcamlConst.CInt(0));
					case "Float": OcamlExpr.EConst(OcamlConst.CFloat("0."));
					case "Bool": OcamlExpr.EConst(OcamlConst.CBool(false));
					case "Null":
						if (params != null && params.length == 1) {
							switch (params[0]) {
								case TAbstract(pRef, _):
									final p = pRef.get();
									switch (p.name) {
										case "Int", "Float", "Bool":
											OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null");
										case _:
											anyNull;
									}
								case _:
									anyNull;
							}
						} else {
							anyNull;
						}
					default: anyNull;
				}
			case TInst(_, _):
				anyNull;
			case TEnum(_, _):
				anyNull;
			case _:
				anyNull;
		}
	}

	/**
		Returns the single runtime-owned exact String null value after validating
		the sealed representation selected for the requested storage domain.
	**/
	function exactStringNullValue(domain:OcamlRepresentationDomain):OcamlExpr {
		final decision = representationRegistry.selectExactString(domain);
		return OcamlStringRepresentationMaterializer.materialize(decision, domain).implicitDefault;
	}

	static function orderLetBindingsForOcaml(lets:Array<OcamlLetBinding>):Array<{bindings:Array<OcamlLetBinding>, isRec:Bool}> {
		if (lets.length <= 1) {
			return lets.length == 0 ? [] : [{bindings: lets, isRec: isSelfRecursive(lets[0].name, lets[0].expr)}];
		}

		final wantSet:Map<String, Bool> = [];
		final nameToIndex:Map<String, Int> = [];
		for (i in 0...lets.length) {
			final name = lets[i].name;
			wantSet.set(name, true);
			nameToIndex.set(name, i);
		}

		// Build dependency graph (user -> deps).
		final deps:Array<Array<Int>> = [];
		final selfRec:Array<Bool> = [];
		for (i in 0...lets.length) {
			final b = lets[i];
			final depNames = collectFreeIdents(b.expr, wantSet);
			final d:Array<Int> = [];
			var isRec = false;
			for (n in depNames.keys()) {
				final j = nameToIndex.get(n);
				d.push(j);
				if (j == i)
					isRec = true;
			}
			deps.push(d);
			selfRec.push(isRec);
		}

		// Tarjan SCC.
		final n = lets.length;
		final index:Array<Int> = [];
		final lowlink:Array<Int> = [];
		final onStack:Array<Bool> = [];
		final stack:Array<Int> = [];
		final sccs:Array<Array<Int>> = [];
		for (_ in 0...n) {
			index.push(-1);
			lowlink.push(0);
			onStack.push(false);
		}
		var nextIndex = 0;

		function minInt(a:Int, b:Int):Int
			return a < b ? a : b;

		function strongconnect(v:Int):Void {
			index[v] = nextIndex;
			lowlink[v] = nextIndex;
			nextIndex++;
			stack.push(v);
			onStack[v] = true;

			for (w in deps[v]) {
				if (index[w] == -1) {
					strongconnect(w);
					lowlink[v] = minInt(lowlink[v], lowlink[w]);
				} else if (onStack[w]) {
					lowlink[v] = minInt(lowlink[v], index[w]);
				}
			}

			if (lowlink[v] == index[v]) {
				final comp:Array<Int> = [];
				while (true) {
					final w = stack.pop();
					onStack[w] = false;
					comp.push(w);
					if (w == v)
						break;
				}
				sccs.push(comp);
			}
		}

		for (v in 0...n) {
			if (index[v] == -1)
				strongconnect(v);
		}

		final sccId:Array<Int> = [];
		for (_ in 0...n)
			sccId.push(-1);
		final sccMinIndex:Array<Int> = [];
		for (sid in 0...sccs.length) {
			var min = 2147483647;
			for (v in sccs[sid]) {
				sccId[v] = sid;
				if (v < min)
					min = v;
			}
			sccMinIndex.push(min);
		}

		// Condensation graph: dep -> user (so deps appear earlier).
		final adj:Array<Map<Int, Bool>> = [];
		final indeg:Array<Int> = [];
		for (_ in 0...sccs.length) {
			adj.push([]);
			indeg.push(0);
		}

		for (u in 0...n) {
			final su = sccId[u];
			for (v in deps[u]) {
				final sv = sccId[v];
				if (su == sv)
					continue;
				if (!adj[sv].exists(su)) {
					adj[sv].set(su, true);
					indeg[su] += 1;
				}
			}
		}

		// Kahn topo-sort with stable tie-breaker (min original index).
		final ready:Array<Int> = [];
		for (sid in 0...sccs.length) {
			if (indeg[sid] == 0)
				ready.push(sid);
		}
		ready.sort((a, b) -> sccMinIndex[a] - sccMinIndex[b]);

		final orderedSccIds:Array<Int> = [];
		while (ready.length > 0) {
			final sid = ready.shift();
			orderedSccIds.push(sid);
			for (to in adj[sid].keys()) {
				indeg[to] -= 1;
				if (indeg[to] == 0) {
					ready.push(to);
					ready.sort((a, b) -> sccMinIndex[a] - sccMinIndex[b]);
				}
			}
		}

		final out:Array<{bindings:Array<OcamlLetBinding>, isRec:Bool}> = [];
		for (sid in orderedSccIds) {
			final nodes = sccs[sid];
			nodes.sort((a, b) -> a - b);
			final groupBindings = nodes.map(i -> lets[i]);
			final rec = nodes.length > 1 || (nodes.length == 1 && selfRec[nodes[0]]);
			out.push({bindings: groupBindings, isRec: rec});
		}
		return out;
	}

	static function isSelfRecursive(name:String, expr:OcamlExpr):Bool {
		final want:Map<String, Bool> = [];
		want.set(name, true);
		final deps = collectFreeIdents(expr, want);
		return deps.exists(name);
	}

	static function collectFreeIdents(expr:OcamlExpr, want:Map<String, Bool>):Map<String, Bool> {
		final out:Map<String, Bool> = [];
		final bound:Map<String, Int> = [];

		function boundAdd(n:String):Void {
			final c = bound.exists(n) ? bound.get(n) : 0;
			bound.set(n, c + 1);
		}

		function boundRemove(n:String):Void {
			if (!bound.exists(n))
				return;
			final c = bound.get(n);
			if (c <= 1)
				bound.remove(n)
			else
				bound.set(n, c - 1);
		}

		function isBound(n:String):Bool
			return bound.exists(n);

		function collectPatNames(p:OcamlPat, acc:Array<String>):Void {
			switch (p) {
				case PAny:
				case PVar(n):
					acc.push(n);
				case PTuple(items):
					for (i in items)
						collectPatNames(i, acc);
				case PRecord(fields):
					for (f in fields)
						collectPatNames(f.pat, acc);
				case PConstructor(_, args):
					for (a in args)
						collectPatNames(a, acc);
				case POr(items):
					for (i in items)
						collectPatNames(i, acc);
				case PAnnot(pat, _):
					collectPatNames(pat, acc);
				case PConst(_):
			}
		}

		function visit(e:OcamlExpr):Void {
			switch (e) {
				case EPos(_, inner):
					visit(inner);
				case EConst(_):
				case ERaw(_):
				case EAnnot(expr, _):
					visit(expr);
				case ERaise(exn):
					visit(exn);
				case EIdent(n):
					if (!isBound(n) && want.exists(n))
						out.set(n, true);
				case ERuntimeIdent(reference):
					if (!isBound(reference.exactSymbol) && want.exists(reference.exactSymbol))
						out.set(reference.exactSymbol, true);
				case ELet(n, value, body, isRec):
					if (isRec) {
						boundAdd(n);
						visit(value);
						visit(body);
						boundRemove(n);
					} else {
						visit(value);
						boundAdd(n);
						visit(body);
						boundRemove(n);
					}
				case EFun(params, body):
					final names:Array<String> = [];
					for (p in params)
						collectPatNames(p, names);
					for (n in names)
						boundAdd(n);
					visit(body);
					for (n in names)
						boundRemove(n);
				case EApp(fn, args):
					visit(fn);
					for (a in args)
						visit(a);
				case EAppArgs(fn, args):
					visit(fn);
					for (a in args)
						visit(a.expr);
				case EBinop(_, l, r):
					visit(l);
					visit(r);
				case EUnop(_, e1):
					visit(e1);
				case EIf(c, t, f):
					visit(c);
					visit(t);
					visit(f);
				case EMatch(scrutinee, cases):
					visit(scrutinee);
					for (c in cases) {
						final names:Array<String> = [];
						collectPatNames(c.pat, names);
						for (n in names)
							boundAdd(n);
						if (c.guard != null)
							visit(c.guard);
						visit(c.expr);
						for (n in names)
							boundRemove(n);
					}
				case ETry(body, cases):
					visit(body);
					for (c in cases) {
						final names:Array<String> = [];
						collectPatNames(c.pat, names);
						for (n in names)
							boundAdd(n);
						if (c.guard != null)
							visit(c.guard);
						visit(c.expr);
						for (n in names)
							boundRemove(n);
					}
				case ESeq(items):
					for (i in items)
						visit(i);
				case EWhile(c, b):
					visit(c);
					visit(b);
				case EList(items):
					for (i in items)
						visit(i);
				case ERecord(fields):
					for (f in fields)
						visit(f.value);
				case EField(e1, _):
					visit(e1);
				case EAssign(_, l, r):
					visit(l);
					visit(r);
				case ETuple(items):
					for (i in items)
						visit(i);
			}
		}

		visit(expr);
		return out;
	}
}
#end
