package hxhx;

import hxhx.runtime.NullableRuntimeString;

/**
	Stage3 customization activation helpers.

	The first supported customization is intentionally diagnostic-only. It proves
	that `hxhx` can activate an explicit compiler customization and disable it
	again without changing parser, resolver, typer, macro, or backend semantics.
	Future behavior-changing customizations should grow behind the architecture
	contract in `docs/00-project/HXHX_CUSTOMIZATION_AND_VARIATION_ARCHITECTURE.md`.
**/
class Stage3CustomizationSupport {
	public static inline var REPORT_TYPED_SUMMARY = "report-typed-summary";

	static function trim(value:String):String {
		return NullableRuntimeString.trimToEmpty(value);
	}

	static function splitRawValue(raw:String):Array<String> {
		final out = new Array<String>();
		final value = trim(raw);
		if (value.length == 0)
			return out;
		final parts = value.indexOf(";") != -1 ? value.split(";") : value.split(",");
		for (part in parts) {
			final normalized = trim(part);
			if (normalized.length > 0 && out.indexOf(normalized) == -1)
				out.push(normalized);
		}
		return out;
	}

	/**
		Normalize and validate Stage3 customization IDs.

		Unknown IDs fail before compilation so a typo cannot silently change a
		baseline lane or create an undocumented variation profile.
	**/
	public static function normalize(raw:Array<String>):Array<String> {
		final out = new Array<String>();
		if (raw == null)
			return out;
		for (entry in raw) {
			for (id in splitRawValue(entry)) {
				switch (id) {
					case REPORT_TYPED_SUMMARY:
						if (out.indexOf(id) == -1)
							out.push(id);
					case _:
						throw "unsupported --hxhx-customization: " + id + " (supported: " + REPORT_TYPED_SUMMARY + ")";
				}
			}
		}
		return out;
	}

	static function has(customizations:Array<String>, id:String):Bool {
		return customizations != null && customizations.indexOf(id) != -1;
	}

	/**
		Emit a deterministic diagnostic-only customization report.

		This deliberately consumes values Stage3 already computed. It does not
		inspect or mutate typed modules, backend registrations, macro state, or
		compiler configuration.
	**/
	public static function emitTypedSummaryReport(customizations:Array<String>, phase:String, backendId:String, typedModules:Int, headerOnlyModules:Int,
			unsupportedExprsTotal:Int, unsupportedFiles:Int):Void {
		if (!has(customizations, REPORT_TYPED_SUMMARY))
			return;
		Sys.println("hxhx_customization[" + REPORT_TYPED_SUMMARY + "]=enabled");
		Sys.println("hxhx_customization_report[" + REPORT_TYPED_SUMMARY + "].phase=" + phase);
		Sys.println("hxhx_customization_report[" + REPORT_TYPED_SUMMARY + "].backend=" + backendId);
		Sys.println("hxhx_customization_report[" + REPORT_TYPED_SUMMARY + "].typed_modules=" + typedModules);
		Sys.println("hxhx_customization_report[" + REPORT_TYPED_SUMMARY + "].header_only_modules=" + headerOnlyModules);
		Sys.println("hxhx_customization_report[" + REPORT_TYPED_SUMMARY + "].unsupported_exprs_total=" + unsupportedExprsTotal);
		Sys.println("hxhx_customization_report[" + REPORT_TYPED_SUMMARY + "].unsupported_files=" + unsupportedFiles);
	}
}
