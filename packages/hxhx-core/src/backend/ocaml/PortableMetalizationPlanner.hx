package backend.ocaml;

import backend.GenIrProgram;
import backend.OcamlProfile;
import backend.ocaml.PortableMetalizationPlan.PortableMetalizationExclusion;
import backend.ocaml.PortableMetalizationPlan.PortableMetalizationRegionSeed;

/**
	Stage3 portable auto-metalization planner.

	Why
	- We need deterministic region classification before emission so portable builds can
	  opt into selected metal-style lowerings without changing the portable contract.
	- Reporting this plan makes decisions reviewable and keeps future profile changes auditable.

	What
	- Enumerates all parsed class functions as candidate regions.
	- Uses metal verifier diagnostics as exclusion signals.
	- Produces one plan object consumed by emission and one JSON report artifact.

	How
	- Build ordered region seeds directly from parsed module/class/function order.
	- Group verifier exclusions by region key (`<file>::<Class>.<function>`).
	- For non-portable profiles, planner stays disabled but still emits a deterministic report.
**/
class PortableMetalizationPlanner {
	public static inline var REPORT_FILE_NAME = "ocaml_portable_metalization_plan_report.json";

	public static function buildPlan(program:GenIrProgram, profile:OcamlProfile):PortableMetalizationPlan {
		final regionSeeds = collectFunctionRegions(program);
		final plannerEnabled = profile == OcamlProfile.Portable;
		if (!plannerEnabled) {
			return new PortableMetalizationPlan(profile, false, regionSeeds, new haxe.ds.StringMap<Bool>(),
				new haxe.ds.StringMap<Array<PortableMetalizationExclusion>>());
		}

		final exclusionsByRegionKey = new haxe.ds.StringMap<Array<PortableMetalizationExclusion>>();
		final summaries = MetalProfileVerifier.collectViolationSummaries(program);
		for (summary in summaries) {
			if (!isFunctionContext(summary.context))
				continue;
			final regionKey = regionKeyFromContext(summary.filePath, summary.context);
			var exclusions = exclusionsByRegionKey.get(regionKey);
			if (exclusions == null) {
				exclusions = [];
				exclusionsByRegionKey.set(regionKey, exclusions);
			}
			appendExclusion(exclusions, summary.code, summary.reason);
		}

		final autoMetalizedRegionKeys = new haxe.ds.StringMap<Bool>();
		for (seed in regionSeeds) {
			if (!exclusionsByRegionKey.exists(seed.regionKey))
				autoMetalizedRegionKeys.set(seed.regionKey, true);
		}
		return new PortableMetalizationPlan(profile, true, regionSeeds, autoMetalizedRegionKeys, exclusionsByRegionKey);
	}

	public static function writeReport(outDir:String, plan:PortableMetalizationPlan):String {
		final normalizedDir = outDir == null ? "" : haxe.io.Path.normalize(outDir);
		if (normalizedDir.length == 0)
			throw "portable metalization planner: missing output directory";
		if (!sys.FileSystem.exists(normalizedDir))
			sys.FileSystem.createDirectory(normalizedDir);
		final reportPath = haxe.io.Path.join([normalizedDir, REPORT_FILE_NAME]);
		final reportJson = haxe.format.JsonPrinter.print(plan.toReport(), null, "  ");
		sys.io.File.saveContent(reportPath, reportJson + "\n");
		return reportPath;
	}

	public static function functionRegionKey(filePath:String, className:String, functionName:String):String {
		return regionKeyFromContext(filePath, contextName(className, functionName));
	}

	static function collectFunctionRegions(program:GenIrProgram):Array<PortableMetalizationRegionSeed> {
		final regions = new Array<PortableMetalizationRegionSeed>();
		for (typedModule in program.getTypedModules()) {
			final parsed = typedModule.getParsed();
			final filePath = normalizeFilePath(parsed.getFilePath());
			final decl = parsed.getDecl();
			for (cls in HxModuleDecl.getClasses(decl)) {
				final className = normalizeClassName(HxClassDecl.getName(cls));
				for (fn in HxClassDecl.getFunctions(cls)) {
					final functionName = normalizeFunctionName(HxFunctionDecl.getName(fn));
					final context = contextName(className, functionName);
					regions.push({
						regionKey: regionKeyFromContext(filePath, context),
						filePath: filePath,
						className: className,
						functionName: functionName,
						context: context
					});
				}
			}
		}
		return regions;
	}

	static function appendExclusion(exclusions:Array<PortableMetalizationExclusion>, code:String, reason:String):Void {
		final normalizedCode = normalizeToken(code);
		final normalizedReason = normalizeReason(reason);
		for (existing in exclusions) {
			if (existing.code == normalizedCode && existing.reason == normalizedReason)
				return;
		}
		exclusions.push({
			code: normalizedCode,
			reason: normalizedReason
		});
	}

	static inline function isFunctionContext(context:String):Bool {
		return context != null && context.indexOf(".") > 0;
	}

	static function regionKeyFromContext(filePath:String, context:String):String {
		return normalizeFilePath(filePath) + "::" + normalizeContext(context);
	}

	static function contextName(className:String, functionName:String):String {
		return normalizeClassName(className) + "." + normalizeFunctionName(functionName);
	}

	static function normalizeContext(context:String):String {
		if (context == null)
			return "<unknown>.<unknown>";
		final trimmed = StringTools.trim(context);
		return trimmed.length == 0 ? "<unknown>.<unknown>" : trimmed;
	}

	static function normalizeFilePath(filePath:String):String {
		if (filePath == null)
			return "<unknown>";
		final trimmed = StringTools.trim(filePath);
		return trimmed.length == 0 ? "<unknown>" : trimmed;
	}

	static function normalizeClassName(className:String):String {
		if (className == null)
			return "<unknown>";
		final trimmed = StringTools.trim(className);
		return trimmed.length == 0 ? "<unknown>" : trimmed;
	}

	static function normalizeFunctionName(functionName:String):String {
		if (functionName == null)
			return "<unknown>";
		final trimmed = StringTools.trim(functionName);
		return trimmed.length == 0 ? "<unknown>" : trimmed;
	}

	static function normalizeToken(raw:String):String {
		if (raw == null)
			return "";
		return StringTools.trim(raw);
	}

	static function normalizeReason(raw:String):String {
		if (raw == null)
			return "";
		return StringTools.trim(StringTools.replace(StringTools.replace(raw, "\r", " "), "\n", " "));
	}
}
