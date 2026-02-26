package backend.ocaml;

import backend.OcamlProfile;

typedef PortableMetalizationRegionReport = {
	final regionKey:String;
	final filePath:String;
	final className:String;
	final functionName:String;
	final context:String;
	final status:String;
	final reasonCodes:Array<String>;
	final exclusionReasons:Array<String>;
	final usedMetalStyleLowerings:Array<String>;
}

typedef PortableMetalizationExcludedCodeReport = {
	final code:String;
	final count:Int;
}

typedef PortableMetalizationSummaryReport = {
	final totalRegions:Int;
	final autoMetalizedRegions:Int;
	final excludedRegions:Int;
	final usedMetalStyleRegions:Int;
}

typedef PortableMetalizationPlanReport = {
	final schemaVersion:Int;
	final profile:String;
	final plannerMode:String;
	final summary:PortableMetalizationSummaryReport;
	final excludedByCode:Array<PortableMetalizationExcludedCodeReport>;
	final regions:Array<PortableMetalizationRegionReport>;
}

typedef PortableMetalizationRegionSeed = {
	final regionKey:String;
	final filePath:String;
	final className:String;
	final functionName:String;
	final context:String;
}

typedef PortableMetalizationExclusion = {
	final code:String;
	final reason:String;
}

/**
	Portable auto-metalization planner state.

	Why
	- Portable mode is the compatibility lane, but we still want a deterministic way to
	  detect "metal-safe" regions where we can apply metal-style lowerings.
	- Emission-time checks should not rescan the typed program repeatedly. We instead build
	  one plan up front and let emitter hot paths query it.

	What
	- Stores per-function region eligibility (`auto_metalized` vs `excluded`).
	- Tracks exclusion reasons derived from metal verifier diagnostics.
	- Records which metal-style lowerings were actually used during emission.
	- Produces a stable, versioned report artifact consumed by tests/CI.

	How
	- Region keys are deterministic and file-scoped: `<file>::<Class>.<function>`.
	- Exclusion reasons are grouped per region and deduplicated in first-seen order.
	- Lowering usage is tracked as a set and sorted during report rendering.

	Gotchas
	- This plan is strictly per-emission-run state. Do not reuse across runs.
	- Planner enablement is profile-bound: only `portable` currently performs auto-metalization.
**/
class PortableMetalizationPlan {
	public static inline var SCHEMA_VERSION = 1;
	public static inline var PLANNER_MODE_PORTABLE = "portable_auto_metalization";
	public static inline var PLANNER_MODE_DISABLED = "disabled_non_portable_profile";

	public final profile:OcamlProfile;
	public final plannerEnabled:Bool;

	final orderedSeeds:Array<PortableMetalizationRegionSeed>;
	final autoMetalizedRegionKeys:haxe.ds.StringMap<Bool>;
	final exclusionsByRegionKey:haxe.ds.StringMap<Array<PortableMetalizationExclusion>>;
	final usedLoweringsByRegionKey:haxe.ds.StringMap<haxe.ds.StringMap<Bool>>;

	public function new(profile:OcamlProfile, plannerEnabled:Bool, orderedSeeds:Array<PortableMetalizationRegionSeed>,
			autoMetalizedRegionKeys:haxe.ds.StringMap<Bool>, exclusionsByRegionKey:haxe.ds.StringMap<Array<PortableMetalizationExclusion>>) {
		this.profile = profile;
		this.plannerEnabled = plannerEnabled;
		this.orderedSeeds = orderedSeeds == null ? [] : orderedSeeds;
		this.autoMetalizedRegionKeys = autoMetalizedRegionKeys == null ? new haxe.ds.StringMap<Bool>() : autoMetalizedRegionKeys;
		this.exclusionsByRegionKey = exclusionsByRegionKey == null ? new haxe.ds.StringMap<Array<PortableMetalizationExclusion>>() : exclusionsByRegionKey;
		this.usedLoweringsByRegionKey = new haxe.ds.StringMap<haxe.ds.StringMap<Bool>>();
	}

	public inline function isAutoMetalized(regionKey:String):Bool {
		return plannerEnabled && regionKey != null && autoMetalizedRegionKeys.exists(regionKey);
	}

	public function markLoweringUsed(regionKey:String, lowering:String):Void {
		if (!isAutoMetalized(regionKey))
			return;
		final normalizedLowering = normalizeToken(lowering);
		if (normalizedLowering.length == 0)
			return;
		var used = usedLoweringsByRegionKey.get(regionKey);
		if (used == null) {
			used = new haxe.ds.StringMap<Bool>();
			usedLoweringsByRegionKey.set(regionKey, used);
		}
		used.set(normalizedLowering, true);
	}

	public function toReport():PortableMetalizationPlanReport {
		final regions = new Array<PortableMetalizationRegionReport>();
		final excludedCodeCounts = new haxe.ds.StringMap<Int>();
		var autoMetalizedCount = 0;
		var excludedCount = 0;
		var usedMetalStyleCount = 0;

		for (seed in orderedSeeds) {
			final autoMetalized = isAutoMetalized(seed.regionKey);
			if (autoMetalized)
				autoMetalizedCount += 1;
			final exclusions = exclusionsByRegionKey.get(seed.regionKey);
			final reasonCodes = new Array<String>();
			final exclusionReasons = new Array<String>();
			if (exclusions != null) {
				for (entry in exclusions) {
					final code = normalizeToken(entry.code);
					if (code.length > 0 && reasonCodes.indexOf(code) < 0)
						reasonCodes.push(code);
					final reasonText = normalizeReason(entry.reason);
					if (reasonText.length > 0 && exclusionReasons.indexOf(reasonText) < 0)
						exclusionReasons.push(reasonText);
				}
			}
			if (!autoMetalized) {
				excludedCount += 1;
				for (code in reasonCodes) {
					final previous = excludedCodeCounts.get(code);
					excludedCodeCounts.set(code, previous == null ? 1 : previous + 1);
				}
			}
			final usedLowerings = sortedKeys(usedLoweringsByRegionKey.get(seed.regionKey));
			if (usedLowerings.length > 0)
				usedMetalStyleCount += 1;
			regions.push({
				regionKey: seed.regionKey,
				filePath: seed.filePath,
				className: seed.className,
				functionName: seed.functionName,
				context: seed.context,
				status: autoMetalized ? "auto_metalized" : "excluded",
				reasonCodes: reasonCodes,
				exclusionReasons: exclusionReasons,
				usedMetalStyleLowerings: usedLowerings
			});
		}

		final excludedByCode = new Array<PortableMetalizationExcludedCodeReport>();
		final sortedCodes = sortedCountKeys(excludedCodeCounts);
		for (code in sortedCodes) {
			final count = excludedCodeCounts.get(code);
			excludedByCode.push({
				code: code,
				count: count == null ? 0 : count
			});
		}

		return {
			schemaVersion: SCHEMA_VERSION,
			profile: OcamlProfile.toDefineValue(profile),
			plannerMode: plannerEnabled ? PLANNER_MODE_PORTABLE : PLANNER_MODE_DISABLED,
			summary: {
				totalRegions: orderedSeeds.length,
				autoMetalizedRegions: autoMetalizedCount,
				excludedRegions: excludedCount,
				usedMetalStyleRegions: usedMetalStyleCount
			},
			excludedByCode: excludedByCode,
			regions: regions
		};
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

	static function sortedKeys(map:haxe.ds.StringMap<Bool>):Array<String> {
		final keys = new Array<String>();
		if (map == null)
			return keys;
		for (key in map.keys())
			keys.push(key);
		keys.sort(compareStrings);
		return keys;
	}

	static function sortedCountKeys(map:haxe.ds.StringMap<Int>):Array<String> {
		final keys = new Array<String>();
		if (map == null)
			return keys;
		for (key in map.keys())
			keys.push(key);
		keys.sort(compareStrings);
		return keys;
	}

	static function compareStrings(a:String, b:String):Int {
		return a < b ? -1 : (a > b ? 1 : 0);
	}
}
