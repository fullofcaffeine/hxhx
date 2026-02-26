package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)
import haxe.io.Path;
import reflaxe.output.OutputManager;
import reflaxe.ocaml.OcamlBuildContext;
import reflaxe.ocaml.OcamlAtomicSemantics;
import reflaxe.ocaml.OcamlProfileContract;
import reflaxe.ocaml.OcamlPortableNativeSurfacePolicy;
import reflaxe.ocaml.OcamlRuntimeMode;
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

class RuntimeCopier {
	static inline final HXHX_RUNTIME_PREFIX = "HxHx";
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
		} catch (_:haxe.Exception) {
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

	static function moduleNameFromRuntimeFile(fileName:String):Null<String> {
		if (StringTools.endsWith(fileName, ".mli"))
			return fileName.substr(0, fileName.length - 4);
		if (StringTools.endsWith(fileName, ".ml"))
			return fileName.substr(0, fileName.length - 3);
		return null;
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

	static function addReferencedModules(content:String, availableModules:Array<String>, selectedModules:Map<String, Bool>, enqueue:Array<String>,
			reasonMap:Map<String, Map<String, Bool>>, reason:String):Void {
		for (moduleName in availableModules) {
			if (selectedModules.exists(moduleName))
				continue;
			if (containsModuleToken(content, moduleName)) {
				selectedModules.set(moduleName, true);
				enqueue.push(moduleName);
				addInclusionReason(reasonMap, moduleName, reason);
			}
		}
	}

	static function enqueueModule(moduleName:String, availableModuleSet:Map<String, Bool>, selectedModules:Map<String, Bool>, enqueue:Array<String>,
			reasonMap:Map<String, Map<String, Bool>>, reason:String):Void {
		if (moduleName == null || moduleName.length == 0)
			return;
		if (!availableModuleSet.exists(moduleName))
			return;
		if (selectedModules.exists(moduleName))
			return;
		selectedModules.set(moduleName, true);
		enqueue.push(moduleName);
		addInclusionReason(reasonMap, moduleName, reason);
	}

	static function availableModuleSet(availableModules:Array<String>):Map<String, Bool> {
		final out:Map<String, Bool> = [];
		for (moduleName in availableModules)
			out.set(moduleName, true);
		return out;
	}

	static function collectSelectiveRuntimeModules(runtimeDir:String, availableModules:Array<String>, trackedSeedModules:Array<String>,
			manualSeedModules:Array<String>, outputDir:Null<String>, destSubdir:String, tokenScanFallbackEnabled:Bool,
			inclusionReasonMap:Map<String, Map<String, Bool>>):Map<String, Bool> {
		final moduleSet = availableModuleSet(availableModules);
		final selectedModules:Map<String, Bool> = [];
		final queue:Array<String> = [];
		enqueueModule(RUNTIME_CORE_MODULE, moduleSet, selectedModules, queue, inclusionReasonMap, "core_runtime");
		for (moduleName in trackedSeedModules) {
			enqueueModule(moduleName, moduleSet, selectedModules, queue, inclusionReasonMap, "compiler_tracked");
		}
		for (moduleName in manualSeedModules) {
			enqueueModule(moduleName, moduleSet, selectedModules, queue, inclusionReasonMap, "manual_seed");
		}

		if (tokenScanFallbackEnabled && outputDir != null && outputDir.length > 0) {
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
				addReferencedModules(content, availableModules, selectedModules, queue, inclusionReasonMap, "token_scan");
			}
		}

		while (queue.length > 0) {
			final moduleName = queue.pop();
			if (moduleName == null)
				continue;
			final mlPath = Path.join([runtimeDir, moduleName + ".ml"]);
			if (sys.FileSystem.exists(mlPath) && !sys.FileSystem.isDirectory(mlPath)) {
				final content = sys.io.File.getContent(mlPath);
				addReferencedModules(content, availableModules, selectedModules, queue, inclusionReasonMap, "transitive:" + moduleName);
			}
			final mliPath = Path.join([runtimeDir, moduleName + ".mli"]);
			if (sys.FileSystem.exists(mliPath) && !sys.FileSystem.isDirectory(mliPath)) {
				final content = sys.io.File.getContent(mliPath);
				addReferencedModules(content, availableModules, selectedModules, queue, inclusionReasonMap, "transitive:" + moduleName);
			}
		}

		return selectedModules;
	}

	static function mapKeysSorted(values:Map<String, Bool>):Array<String> {
		final out = new Array<String>();
		for (name in values.keys())
			out.push(name);
		out.sort(compareStrings);
		return out;
	}

	static function trackedModulesSorted(trackedModules:Array<String>, availableModules:Array<String>):Array<String> {
		final availableSet = availableModuleSet(availableModules);
		final selected:Map<String, Bool> = [];
		for (moduleName in trackedModules) {
			if (moduleName == null || moduleName.length == 0)
				continue;
			if (!availableSet.exists(moduleName))
				continue;
			selected.set(moduleName, true);
		}
		return mapKeysSorted(selected);
	}

	static function runtimeSelectionModeLabel(context:OcamlBuildContext, compilerTrackedModules:Array<String>, manualModules:Array<String>):String {
		return switch (context.runtimeMode) {
			case Full:
				"full";
			case Selective:
				final hasTracked = compilerTrackedModules.length > 0;
				final hasManual = manualModules.length > 0;
				final base = if (hasTracked && hasManual) "compiler_tracked_plus_manual" else if (hasTracked) "compiler_tracked" else if (hasManual)
					"manual_only" else "minimal_core";
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

	static function writeProfileReport(output:OutputManager, requested:Null<String>, context:OcamlBuildContext):Void {
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
	}

	static function writeRuntimePlanReport(output:OutputManager, context:OcamlBuildContext, selectionMode:String, availableModules:Array<String>,
			trackedModules:Array<String>, manualModules:Array<String>, selectedModules:Array<String>, inclusionReasons:Array<RuntimePlanInclusionReason>):Void {
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
	}

	public static function copy(output:OutputManager, destSubdir:String = "runtime", compilerTrackedModules:Array<String>):Void {
		final stdDir = tryResolveStdDir();
		if (stdDir == null)
			return;

		final runtimeDir = Path.join([stdDir, "runtime"]);
		if (!sys.FileSystem.exists(runtimeDir) || !sys.FileSystem.isDirectory(runtimeDir))
			return;

		#if macro
		final allowHxHxRuntime = haxe.macro.Context.defined("hih_native_parser")
			|| haxe.macro.Context.defined("hxhx_native_frontend")
			|| haxe.macro.Context.defined("hxhx");
		#else
		final allowHxHxRuntime = false;
		#end

		final runtimeFiles = sys.FileSystem.readDirectory(runtimeDir);
		runtimeFiles.sort(compareStrings);

		final availableModules:Array<String> = [];
		final availableModuleSet:Map<String, Bool> = [];
		for (name in runtimeFiles) {
			final moduleName = moduleNameFromRuntimeFile(name);
			if (moduleName == null)
				continue;
			if (!allowHxHxRuntime && StringTools.startsWith(moduleName, HXHX_RUNTIME_PREFIX))
				continue;
			if (!availableModuleSet.exists(moduleName)) {
				availableModuleSet.set(moduleName, true);
				availableModules.push(moduleName);
			}
		}
		availableModules.sort(compareStrings);
		final trackedModulesAll = trackedModulesSorted(compilerTrackedModules != null ? compilerTrackedModules : [], availableModules);
		final rawRequestedProfile = requestedProfile();
		final buildContext = OcamlBuildContext.resolve();
		final trackedModules = buildContext.runtimeMode == Selective && !buildContext.runtimeInferenceDisabled ? trackedModulesAll : [];
		final manualModules = trackedModulesSorted(buildContext.runtimeManualModules, availableModules);
		final selectionMode = runtimeSelectionModeLabel(buildContext, trackedModules, manualModules);
		final inclusionReasonMap:Map<String, Map<String, Bool>> = [];
		final selectedModules:Map<String, Bool> = switch (buildContext.runtimeMode) {
			case Selective:
				collectSelectiveRuntimeModules(runtimeDir, availableModules, trackedModules, manualModules, output.outputDir, destSubdir,
					buildContext.runtimeTokenScanFallbackEnabled, inclusionReasonMap);
			case Full:
				final all:Map<String, Bool> = [];
				for (moduleName in availableModules) {
					all.set(moduleName, true);
					addInclusionReason(inclusionReasonMap, moduleName, "full_runtime_mode");
				}
				all;
		}
		final selectedModuleList = mapKeysSorted(selectedModules);
		final inclusionReasons = inclusionReasonsSorted(inclusionReasonMap, selectedModuleList);
		writeProfileReport(output, rawRequestedProfile, buildContext);
		writeRuntimePlanReport(output, buildContext, selectionMode, availableModules.copy(), trackedModules, manualModules, selectedModuleList,
			inclusionReasons);

		for (name in runtimeFiles) {
			final moduleName = moduleNameFromRuntimeFile(name);
			if (moduleName == null || !selectedModules.exists(moduleName))
				continue;
			final src = Path.join([runtimeDir, name]);
			if (!sys.FileSystem.exists(src) || sys.FileSystem.isDirectory(src))
				continue;
			final rel = destSubdir + "/" + name;
			final content = sys.io.File.getContent(src);
			output.saveFile(rel, content);
		}
	}
}
#end
