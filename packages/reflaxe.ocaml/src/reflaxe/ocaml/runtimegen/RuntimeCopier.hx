package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)
import haxe.io.Path;
import reflaxe.output.OutputManager;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestBuilder;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactAuthority;
import reflaxe.ocaml.artifacts.OcamlSourceBundleAuthority;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactOwner;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactSourceKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactStability;
import reflaxe.ocaml.OcamlBuildContext;
import reflaxe.ocaml.OcamlAtomicSemantics;
import reflaxe.ocaml.OcamlProfileContract;
import reflaxe.ocaml.OcamlPortableNativeSurfacePolicy;
import reflaxe.ocaml.OcamlRuntimeMode;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifestModel.RuntimeSourceManifestSnapshot;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifestModel.RuntimeSourceModule;
#if macro
import reflaxe.ocaml.macros.StrictModeEnforcer;
#end

private typedef ProfileReportVerifier = {
	final mode:String;
	final enabled:Bool;
	final result:String;
	final strictScope:String;
	final violationCount:Int;
	final violations:Array<String>;
	final laneModules:Array<String>;
}

private typedef ProfileReport = {
	final schemaVersion:Int;
	final requestedProfile:Null<String>;
	final normalizedProfile:String;
	final atomicSemantics:String;
	final runtimeMode:String;
	final portableNativeSurfacePolicy:String;
	final strictUserBoundaries:Bool;
	final metalFallbackAllowed:Bool;
	final verifier:ProfileReportVerifier;
}

private typedef RuntimePlanInclusionReason = {
	final module:String;
	final reasons:Array<String>;
}

private typedef RuntimePlanReport = {
	final schemaVersion:Int;
	final profile:String;
	final runtimeMode:String;
	final selectionMode:String;
	final availableModules:Array<String>;
	final trackedModules:Array<String>;
	final manualModules:Array<String>;
	final runtimeInferenceDisabled:Bool;
	final runtimeDebugLaneEnabled:Bool;
	final tokenScanFallbackEnabled:Bool;
	final selectedModules:Array<String>;
	final selectedFeatures:Array<String>;
	final inclusionReasons:Array<RuntimePlanInclusionReason>;
}

/**
	Copies the checked runtime dependency closure into generated OCaml projects.

	The source manifest owns file integrity and module-to-module dependencies. This
	class only combines requested roots, resolves their checked closure, writes the
	reports, and copies the selected bytes. It does not infer dependencies by reading
	OCaml source text.
**/
class RuntimeCopier {
	static inline final RUNTIME_CORE_MODULE = "HxRuntime";
	static inline final PROFILE_REPORT_FILE = "ocaml_profile_report.json";
	static inline final RUNTIME_PLAN_REPORT_FILE = "ocaml_runtime_plan_report.json";

	static function tryResolveStdDir():Null<String> {
		#if macro
		try {
			// `std/` is on the classpath via haxe_libraries/reflaxe.ocaml.hxml.
			// Resolve a known file inside it so we can locate `std/runtime/`.
			final ocamlList = haxe.macro.Context.resolvePath("ocaml/List.hx");
			final ocamlDir = Path.directory(ocamlList); // .../std/ocaml
			return Path.directory(ocamlDir); // .../std
		} catch (_:Dynamic) {
			return null;
		}
		#else
		return null;
		#end
	}

	static function requestedProfile():Null<String> {
		#if macro
		return haxe.macro.Context.definedValue("ocaml_profile");
		#else
		return null;
		#end
	}

	static function isIdentifierChar(code:Int):Bool {
		return (code >= "A".code && code <= "Z".code)
			|| (code >= "a".code && code <= "z".code)
			|| (code >= "0".code && code <= "9".code)
			|| code == "_".code;
	}

	static function containsModuleToken(text:String, moduleName:String):Bool {
		if (text == null || moduleName == null || moduleName.length == 0)
			return false;

		var idx = text.indexOf(moduleName, 0);
		while (idx >= 0) {
			final beforeIdx = idx - 1;
			final afterIdx = idx + moduleName.length;
			final beforeCode:Null<Int> = beforeIdx < 0 ? null : text.charCodeAt(beforeIdx);
			final afterCode:Null<Int> = afterIdx >= text.length ? null : text.charCodeAt(afterIdx);
			final beforeOk = beforeCode == null || !isIdentifierChar(beforeCode);
			final afterOk = afterCode == null || !isIdentifierChar(afterCode);
			if (beforeOk && afterOk)
				return true;
			idx = text.indexOf(moduleName, idx + 1);
		}
		return false;
	}

	static function compareStrings(a:String, b:String):Int {
		return a < b ? -1 : (a > b ? 1 : 0);
	}

	static function collectOutputFilesRecursive(dir:String, out:Array<String>):Void {
		if (!sys.FileSystem.exists(dir) || !sys.FileSystem.isDirectory(dir))
			return;
		for (name in sys.FileSystem.readDirectory(dir)) {
			final path = Path.join([dir, name]);
			if (sys.FileSystem.isDirectory(path)) {
				collectOutputFilesRecursive(path, out);
			} else {
				out.push(path);
			}
		}
	}

	static function normalizedPath(path:String):String {
		return path == null ? "" : StringTools.replace(path, "\\", "/");
	}

	#if macro
	static function enabledDefine(name:String):Bool {
		final raw = haxe.macro.Context.definedValue(name);
		if (raw != null)
			return StringTools.trim(raw) != "0";
		return haxe.macro.Context.defined(name);
	}
	#end

	static function addInclusionReason(reasonMap:Map<String, Map<String, Bool>>, moduleName:String, reason:String):Void {
		if (moduleName == null || moduleName.length == 0 || reason == null || reason.length == 0)
			return;
		final existing = reasonMap.get(moduleName);
		if (existing != null) {
			existing.set(reason, true);
		} else {
			final created:Map<String, Bool> = [];
			created.set(reason, true);
			reasonMap.set(moduleName, created);
		}
	}

	static function addReferencedModules(content:String, availableModules:Array<String>, selectedModules:Map<String, Bool>):Void {
		for (moduleName in availableModules) {
			if (containsModuleToken(content, moduleName))
				selectedModules.set(moduleName, true);
		}
	}

	static function collectTokenScanRoots(availableModules:Array<String>, outputDir:Null<String>, destSubdir:String):Array<String> {
		final selectedModules:Map<String, Bool> = [];
		if (outputDir != null && outputDir.length > 0) {
			final outputFiles:Array<String> = [];
			collectOutputFilesRecursive(outputDir, outputFiles);
			outputFiles.sort(compareStrings);

			final runtimePrefix = normalizedPath(Path.join([outputDir, destSubdir])) + "/";
			for (path in outputFiles) {
				final normalizedPathValue = normalizedPath(path);
				if (StringTools.startsWith(normalizedPathValue, runtimePrefix))
					continue;
				if (!StringTools.endsWith(normalizedPathValue, ".ml") && !StringTools.endsWith(normalizedPathValue, ".mli"))
					continue;
				final content = sys.io.File.getContent(path);
				addReferencedModules(content, availableModules, selectedModules);
			}
		}
		return mapKeysSorted(selectedModules);
	}

	static function mapKeysSorted(values:Map<String, Bool>):Array<String> {
		final out = new Array<String>();
		for (name in values.keys())
			out.push(name);
		out.sort(compareStrings);
		return out;
	}

	static function validatedRootsSorted(requestedModules:Array<String>, snapshot:RuntimeSourceManifestSnapshot, label:String):Array<String> {
		final availableSet:Map<String, Bool> = [for (entry in snapshot.modules) entry.module => true];
		final selected:Map<String, Bool> = [];
		for (moduleName in requestedModules) {
			if (moduleName == null || moduleName.length == 0)
				continue;
			if (!availableSet.exists(moduleName))
				throw 'Unknown OCaml runtime module "$moduleName" requested by $label.';
			selected.set(moduleName, true);
		}
		return mapKeysSorted(selected);
	}

	static function addRootReasons(inclusionReasonMap:Map<String, Map<String, Bool>>, modules:Array<String>, reason:String):Void {
		for (moduleName in modules)
			addInclusionReason(inclusionReasonMap, moduleName, reason);
	}

	static function addDependencyReasons(inclusionReasonMap:Map<String, Map<String, Bool>>, selectedModules:Array<RuntimeSourceModule>):Void {
		final selected:Map<String, Bool> = [for (entry in selectedModules) entry.module => true];
		for (entry in selectedModules)
			for (dependency in entry.dependencies)
				if (selected.exists(dependency))
					addInclusionReason(inclusionReasonMap, dependency, "transitive:" + entry.module);
	}

	static function runtimeSelectionModeLabel(context:OcamlBuildContext, requiredModules:Array<String>, compilerObservedModules:Array<String>,
			manualModules:Array<String>):String {
		return switch (context.runtimeMode) {
			case Full:
				"full";
			case Selective:
				final hasRequirements = requiredModules.length > 0;
				final hasObserved = compilerObservedModules.length > 0;
				final hasManual = manualModules.length > 0;
				final base = if (hasRequirements && hasObserved && hasManual) {
					"requirements_plus_compiler_observed_plus_manual";
				} else if (hasRequirements && hasObserved) {
					"requirements_plus_compiler_observed";
				} else if (hasRequirements && hasManual) {
					"requirements_plus_manual";
				} else if (hasRequirements) {
					"requirements";
				} else if (hasObserved && hasManual) {
					"compiler_observed_plus_manual";
				} else if (hasObserved) {
					"compiler_observed";
				} else if (hasManual) {
					"manual_only";
				} else {
					"minimal_core";
				}
				context.runtimeTokenScanFallbackEnabled ? (base + "_plus_token_scan_fallback") : base;
		}
	}

	static function inclusionReasonsSorted(reasonMap:Map<String, Map<String, Bool>>, selectedModules:Array<String>):Array<RuntimePlanInclusionReason> {
		final out:Array<RuntimePlanInclusionReason> = [];
		for (moduleName in selectedModules) {
			final reasonSet = reasonMap.get(moduleName);
			final reasons:Array<String> = [];
			if (reasonSet != null) {
				for (reason in reasonSet.keys())
					reasons.push(reason);
				reasons.sort(compareStrings);
			}
			out.push({
				module: moduleName,
				reasons: reasons
			});
		}
		return out;
	}

	static function writeProfileReport(output:OutputManager, artifacts:OcamlArtifactManifestBuilder, requested:Null<String>, context:OcamlBuildContext):Void {
		#if macro
		final strictSnapshot = StrictModeEnforcer.snapshot();
		#else
		final strictSnapshot:ProfileReportVerifier = {
			mode: "reflaxe_stage0_macro",
			enabled: false,
			result: "not_enabled",
			strictScope: "disabled",
			violationCount: 0,
			violations: [],
			laneModules: []
		};
		#end
		final report:ProfileReport = {
			schemaVersion: 2,
			requestedProfile: requested,
			normalizedProfile: OcamlProfileContract.toDefineValue(context.profile),
			atomicSemantics: OcamlAtomicSemantics.toDefineValue(context.atomicSemantics),
			runtimeMode: OcamlRuntimeMode.toDefineValue(context.runtimeMode),
			portableNativeSurfacePolicy: OcamlPortableNativeSurfacePolicy.toDefineValue(context.portableNativeSurfacePolicy),
			strictUserBoundaries: context.strictUserBoundaries,
			metalFallbackAllowed: context.metalFallbackAllowed,
			verifier: {
				mode: strictSnapshot.mode,
				enabled: strictSnapshot.enabled,
				result: strictSnapshot.result,
				strictScope: strictSnapshot.strictScope,
				violationCount: strictSnapshot.violationCount,
				violations: strictSnapshot.violations.copy(),
				laneModules: strictSnapshot.laneModules.copy()
			}
		};
		output.saveFile(PROFILE_REPORT_FILE, haxe.Json.stringify(report, null, "  ") + "\n");
		recordReport(artifacts, PROFILE_REPORT_FILE);
	}

	static function writeRuntimePlanReport(output:OutputManager, artifacts:OcamlArtifactManifestBuilder, context:OcamlBuildContext, selectionMode:String,
			availableModules:Array<String>, trackedModules:Array<String>, manualModules:Array<String>, selectedModules:Array<String>,
			inclusionReasons:Array<RuntimePlanInclusionReason>):Void {
		final report:RuntimePlanReport = {
			schemaVersion: 2,
			profile: OcamlProfileContract.toDefineValue(context.profile),
			runtimeMode: OcamlRuntimeMode.toDefineValue(context.runtimeMode),
			selectionMode: selectionMode,
			availableModules: availableModules,
			trackedModules: trackedModules,
			manualModules: manualModules,
			runtimeInferenceDisabled: context.runtimeInferenceDisabled,
			runtimeDebugLaneEnabled: context.runtimeDebugLaneEnabled,
			tokenScanFallbackEnabled: context.runtimeTokenScanFallbackEnabled,
			selectedModules: selectedModules,
			selectedFeatures: selectedModules.copy(),
			inclusionReasons: inclusionReasons
		};
		output.saveFile(RUNTIME_PLAN_REPORT_FILE, haxe.Json.stringify(report, null, "  ") + "\n");
		recordReport(artifacts, RUNTIME_PLAN_REPORT_FILE);
	}

	static function recordReport(artifacts:OcamlArtifactManifestBuilder, path:String):Void {
		artifacts.record({
			path: path,
			kind: OcamlArtifactKind.CompilerReport,
			owner: OcamlArtifactOwner.RuntimePackaging,
			sourceKind: OcamlArtifactSourceKind.Generated,
			sourcePath: null,
			license: "generated-output",
			profileEligibility: ["portable", "metal"],
			stability: OcamlArtifactStability.Stable,
			includeInSourceBundle: false
		});
	}

	public static function copy(output:OutputManager, artifacts:OcamlArtifactManifestBuilder, destSubdir:String = "runtime",
			compilerObservedModules:Array<String>, programOwnedModules:Array<String>, requirements:Array<OcamlRuntimeRequirement>,
			requirementRevision:String):OcamlArtifactAuthority {
		final stdDir = tryResolveStdDir();
		if (stdDir == null)
			throw "Cannot locate the reflaxe.ocaml standard library, so the checked OCaml runtime cannot be packaged.";

		final runtimeDir = Path.join([stdDir, "runtime"]);
		if (!sys.FileSystem.exists(runtimeDir) || !sys.FileSystem.isDirectory(runtimeDir))
			throw 'The reflaxe.ocaml runtime source directory "$runtimeDir" is missing.';

		#if macro
		final allowHxHxRuntime = enabledDefine("hih_native_parser")
			|| enabledDefine("hxhx_native_frontend")
			|| enabledDefine("hxhx")
			|| enabledDefine("hxhx_backend_plugin_host_runtime")
			|| enabledDefine("hxhx_macro_host");
		#else
		final allowHxHxRuntime = false;
		#end

		final rawRequestedProfile = requestedProfile();
		final buildContext = OcamlBuildContext.resolve();
		final profile = OcamlProfileContract.toDefineValue(buildContext.profile);
		final sourceManifest = RuntimeSourceManifest.load(runtimeDir);
		final availableModules = [
			for (entry in sourceManifest.modules)
				if (entry.profiles.contains(profile)
					&& (allowHxHxRuntime || entry.scope != RuntimeSourceManifest.TOOLING_SCOPE)) entry.module
		];
		final runtimeCatalogModules = [for (entry in sourceManifest.modules) entry.module];
		final observationPartition = RuntimeModuleOwnership.partitionCompilerObservations(compilerObservedModules, programOwnedModules, runtimeCatalogModules);
		final compilerObservedModulesAll = validatedRootsSorted(observationPartition.runtimeModules, sourceManifest, "compiler-observed generated output");
		if (compilerObservedModulesAll.length > 0)
			RuntimeSourceManifest.resolveClosure(sourceManifest, compilerObservedModulesAll, profile, allowHxHxRuntime);
		final enabledCompilerObservedModules = buildContext.runtimeMode == Selective
			&& !buildContext.runtimeInferenceDisabled ? compilerObservedModulesAll : [];
		final manualModules = validatedRootsSorted(buildContext.runtimeManualModules, sourceManifest, "-D ocaml_runtime_modules");
		final recordedRequirements = requirements != null ? requirements : [];
		final requiredSet:Map<String, Bool> = [];
		for (requirement in recordedRequirements) {
			if (!requirement.profileEligibility.contains(profile))
				throw 'Recorded OCaml runtime requirement "${requirement.id}" is not eligible for the "$profile" profile.';
			for (moduleName in requirement.rootModules)
				requiredSet.set(moduleName, true);
		}
		final requiredModules = validatedRootsSorted(mapKeysSorted(requiredSet), sourceManifest, "recorded runtime requirements");
		if (requiredModules.length > 0)
			RuntimeSourceManifest.resolveClosure(sourceManifest, requiredModules, profile, allowHxHxRuntime);
		final selectionMode = runtimeSelectionModeLabel(buildContext, requiredModules, enabledCompilerObservedModules, manualModules);
		final inclusionReasonMap:Map<String, Map<String, Bool>> = [];
		final selectedEntries:Array<RuntimeSourceModule> = switch (buildContext.runtimeMode) {
			case Selective:
				final rootSet:Map<String, Bool> = [];
				rootSet.set(RUNTIME_CORE_MODULE, true);
				addInclusionReason(inclusionReasonMap, RUNTIME_CORE_MODULE, "core_runtime");
				for (moduleName in requiredModules)
					rootSet.set(moduleName, true);
				addRootReasons(inclusionReasonMap, requiredModules, "recorded_requirement");
				for (moduleName in enabledCompilerObservedModules)
					rootSet.set(moduleName, true);
				addRootReasons(inclusionReasonMap, enabledCompilerObservedModules, "compiler_observed");
				for (moduleName in manualModules)
					rootSet.set(moduleName, true);
				addRootReasons(inclusionReasonMap, manualModules, "manual_seed");
				if (buildContext.runtimeTokenScanFallbackEnabled) {
					final tokenRoots = collectTokenScanRoots(availableModules, output.outputDir, destSubdir);
					for (moduleName in tokenRoots)
						rootSet.set(moduleName, true);
					addRootReasons(inclusionReasonMap, tokenRoots, "token_scan");
				}
				RuntimeSourceManifest.resolveClosure(sourceManifest, mapKeysSorted(rootSet), profile, allowHxHxRuntime);
			case Full:
				final roots = RuntimeSourceManifest.fullRoots(sourceManifest, profile, allowHxHxRuntime);
				addRootReasons(inclusionReasonMap, roots, "full_runtime_mode");
				RuntimeSourceManifest.resolveClosure(sourceManifest, roots, profile, allowHxHxRuntime);
		}
		if (buildContext.runtimeMode == Selective)
			addDependencyReasons(inclusionReasonMap, selectedEntries);
		final selectedModuleList = [for (entry in selectedEntries) entry.module];
		RuntimeModuleOwnership.assertNoSelectedRuntimeCollisions(programOwnedModules, selectedModuleList);
		final inclusionReasons = inclusionReasonsSorted(inclusionReasonMap, selectedModuleList);
		writeProfileReport(output, artifacts, rawRequestedProfile, buildContext);
		writeRuntimePlanReport(output, artifacts, buildContext, selectionMode, availableModules.copy(), enabledCompilerObservedModules, manualModules,
			selectedModuleList, inclusionReasons);
		OcamlRuntimeRequirementReportWriter.write(output, artifacts, profile, allowHxHxRuntime, buildContext.runtimeMode, selectionMode, sourceManifest,
			recordedRequirements, requirementRevision, compilerObservedModulesAll, selectedEntries);

		for (entry in selectedEntries)
			for (file in entry.files) {
				final src = Path.join([runtimeDir, file.path]);
				final rel = destSubdir + "/" + file.path;
				output.saveFile(rel, sys.io.File.getContent(src));
				artifacts.record({
					path: rel,
					kind: OcamlArtifactKind.RuntimeSource,
					owner: OcamlArtifactOwner.RuntimePackaging,
					sourceKind: OcamlArtifactSourceKind.CopiedRuntime,
					sourcePath: "std/runtime/" + file.path,
					license: entry.license,
					profileEligibility: entry.profiles.copy(),
					stability: OcamlArtifactStability.Stable,
					includeInSourceBundle: true
				});
			}
		return OcamlSourceBundleAuthority.semanticRuntime(sourceManifest, requirementRevision, profile,
			OcamlRuntimeMode.toDefineValue(buildContext.runtimeMode), selectionMode, allowHxHxRuntime, selectedEntries);
	}
}
#end
