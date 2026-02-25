package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)
import haxe.io.Path;
import reflaxe.output.OutputManager;

private typedef ProfileReportVerifier = {
	final mode:String;
	final enabled:Bool;
	final result:String;
}

private typedef ProfileReport = {
	final contractVersion:Int;
	final requestedProfile:Null<String>;
	final normalizedProfile:String;
	final verifier:ProfileReportVerifier;
}

private typedef RuntimePlanReport = {
	final contractVersion:Int;
	final profile:String;
	final selectionMode:String;
	final availableModules:Array<String>;
	final trackedModules:Array<String>;
	final tokenScanFallbackEnabled:Bool;
	final selectedModules:Array<String>;
	final selectedFeatures:Array<String>;
}

class RuntimeCopier {
	static inline final HXHX_RUNTIME_PREFIX = "HxHx";
	static inline final PROFILE_PORTABLE = "portable";
	static inline final PROFILE_METAL = "metal";
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

	static function normalizeProfile(rawProfile:Null<String>):String {
		if (rawProfile == null)
			return PROFILE_PORTABLE;
		final normalized = StringTools.trim(rawProfile).toLowerCase();
		return normalized.length == 0 ? PROFILE_PORTABLE : normalized;
	}

	static function currentProfile():String {
		#if macro
		return normalizeProfile(haxe.macro.Context.definedValue("ocaml_profile"));
		#else
		return PROFILE_PORTABLE;
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

	static function addReferencedModules(content:String, availableModules:Array<String>, selectedModules:Map<String, Bool>, enqueue:Array<String>):Void {
		for (moduleName in availableModules) {
			if (selectedModules.exists(moduleName))
				continue;
			if (containsModuleToken(content, moduleName)) {
				selectedModules.set(moduleName, true);
				enqueue.push(moduleName);
			}
		}
	}

	static function enqueueModule(moduleName:String, availableModuleSet:Map<String, Bool>, selectedModules:Map<String, Bool>, enqueue:Array<String>):Void {
		if (moduleName == null || moduleName.length == 0)
			return;
		if (!availableModuleSet.exists(moduleName))
			return;
		if (selectedModules.exists(moduleName))
			return;
		selectedModules.set(moduleName, true);
		enqueue.push(moduleName);
	}

	static function availableModuleSet(availableModules:Array<String>):Map<String, Bool> {
		final out:Map<String, Bool> = [];
		for (moduleName in availableModules)
			out.set(moduleName, true);
		return out;
	}

	static function collectMetalRuntimeModules(runtimeDir:String, availableModules:Array<String>, compilerTrackedModules:Array<String>,
			outputDir:Null<String>, destSubdir:String, tokenScanFallbackEnabled:Bool):Map<String, Bool> {
		final moduleSet = availableModuleSet(availableModules);
		final selectedModules:Map<String, Bool> = [];
		final queue:Array<String> = [];
		enqueueModule(RUNTIME_CORE_MODULE, moduleSet, selectedModules, queue);
		for (moduleName in compilerTrackedModules) {
			enqueueModule(moduleName, moduleSet, selectedModules, queue);
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
				addReferencedModules(content, availableModules, selectedModules, queue);
			}
		}

		while (queue.length > 0) {
			final moduleName = queue.pop();
			if (moduleName == null)
				continue;
			final mlPath = Path.join([runtimeDir, moduleName + ".ml"]);
			if (sys.FileSystem.exists(mlPath) && !sys.FileSystem.isDirectory(mlPath)) {
				final content = sys.io.File.getContent(mlPath);
				addReferencedModules(content, availableModules, selectedModules, queue);
			}
			final mliPath = Path.join([runtimeDir, moduleName + ".mli"]);
			if (sys.FileSystem.exists(mliPath) && !sys.FileSystem.isDirectory(mliPath)) {
				final content = sys.io.File.getContent(mliPath);
				addReferencedModules(content, availableModules, selectedModules, queue);
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

	static function writeProfileReport(output:OutputManager, requested:Null<String>, normalized:String):Void {
		final report:ProfileReport = {
			contractVersion: 1,
			requestedProfile: requested,
			normalizedProfile: normalized,
			verifier: {
				mode: "reflaxe_stage0_macro",
				enabled: false,
				result: "not_run_in_runtime_copier"
			}
		};
		output.saveFile(PROFILE_REPORT_FILE, haxe.Json.stringify(report, null, "  ") + "\n");
	}

	static function writeRuntimePlanReport(output:OutputManager, profile:String, selectionMode:String, availableModules:Array<String>,
			trackedModules:Array<String>, tokenScanFallbackEnabled:Bool, selectedModules:Array<String>):Void {
		final report:RuntimePlanReport = {
			contractVersion: 1,
			profile: profile,
			selectionMode: selectionMode,
			availableModules: availableModules,
			trackedModules: trackedModules,
			tokenScanFallbackEnabled: tokenScanFallbackEnabled,
			selectedModules: selectedModules,
			selectedFeatures: selectedModules.copy()
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
		final trackedModules = trackedModulesSorted(compilerTrackedModules != null ? compilerTrackedModules : [], availableModules);

		final profile = currentProfile();
		#if macro
		final tokenScanFallbackEnabled = haxe.macro.Context.defined("ocaml_runtime_token_scan_fallback");
		#else
		final tokenScanFallbackEnabled = false;
		#end
		final selectionMode = switch (profile) {
			case PROFILE_METAL:
				tokenScanFallbackEnabled ? "compiler_tracked_plus_token_scan_fallback" : "compiler_tracked";
			case _:
				"full";
		};
		final selectedModules:Map<String, Bool> = switch (profile) {
			case PROFILE_METAL:
				collectMetalRuntimeModules(runtimeDir, availableModules, trackedModules, output.outputDir, destSubdir, tokenScanFallbackEnabled);
			case _:
				final all:Map<String, Bool> = [];
				for (moduleName in availableModules)
					all.set(moduleName, true);
				all;
		}
		final selectedModuleList = mapKeysSorted(selectedModules);
		writeProfileReport(output, requestedProfile(), profile);
		writeRuntimePlanReport(output, profile, selectionMode, availableModules.copy(), trackedModules, tokenScanFallbackEnabled, selectedModuleList);

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
