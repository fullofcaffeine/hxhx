import backend.BackendContext;
import backend.ocaml.OcamlTargetCore;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

private typedef PortableMetalizationSummary = {
	final totalRegions:Int;
	final autoMetalizedRegions:Int;
	final excludedRegions:Int;
	final usedMetalStyleRegions:Int;
}

private typedef PortableMetalizationRegion = {
	final regionKey:String;
	final context:String;
	final status:String;
	final reasonCodes:Array<String>;
	final exclusionReasons:Array<String>;
	final usedMetalStyleLowerings:Array<String>;
}

private typedef PortableMetalizationCodeCount = {
	final code:String;
	final count:Int;
}

private typedef PortableMetalizationReport = {
	final schemaVersion:Int;
	final profile:String;
	final plannerMode:String;
	final summary:PortableMetalizationSummary;
	final regions:Array<PortableMetalizationRegion>;
	final excludedByCode:Array<PortableMetalizationCodeCount>;
}

class M14PortableAutoMetalizationPlannerIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw label + " (missing `" + needle + "`)";
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function readReport(outDir:String):PortableMetalizationReport {
		final reportPath = Path.join([outDir, "ocaml_portable_metalization_plan_report.json"]);
		if (!FileSystem.exists(reportPath))
			throw "missing portable metalization report: " + reportPath;
		return cast haxe.Json.parse(File.getContent(reportPath));
	}

	static function findMainModulePath(outDir:String):String {
		var fallback:Null<String> = null;
		for (entry in FileSystem.readDirectory(outDir)) {
			if (entry == "Main.ml" || entry == "main.ml")
				return Path.join([outDir, entry]);
			if (StringTools.endsWith(entry, "Main.ml")) {
				final candidate = Path.join([outDir, entry]);
				if (!StringTools.endsWith(entry, "_Main.ml") && !StringTools.endsWith(entry, "__Main.ml"))
					return candidate;
				if (fallback == null)
					fallback = candidate;
			}
		}
		if (fallback != null)
			return fallback;
		throw "unable to locate emitted main module in " + outDir;
	}

	static function findRegion(report:PortableMetalizationReport, context:String):PortableMetalizationRegion {
		for (region in report.regions)
			if (region.context == context)
				return region;
		throw "missing region in report for context " + context;
	}

	static function main():Void {
		final tmpRoot = Path.normalize(".tmp/m14_portable_auto_metalization_" + Std.string(Date.now().getTime()));
		final outDir = Path.join([tmpRoot, "out"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		final source = [
			"class Main {",
			"  static function trimWord(word:String):String {",
			"    return StringTools.trim(word);",
			"  }",
			"  static function metalSafeMap(words:Array<String>):Array<String> {",
			"    return words.map(trimWord);",
			"  }",
			"  static function blocked(value:Dynamic):Int {",
			"    return Std.int(Reflect.field({payload: value}, \"payload\"));",
			"  }",
			"  static function main() {",
			"    var normalized = metalSafeMap([\" a \", \"b \"]);",
			"    var blockedValue = blocked(2);",
			"    Sys.println(normalized.join(\",\") + \":\" + Std.string(blockedValue));",
			"  }",
			"}"
		].join("\n");

		var failure:Null<String> = null;
		try {
			final parsed = ParserStage.parse(source, "PortableAutoMetalizationMain.hx");
			final typed = TyperStage.typeModule(parsed);
			final program = MacroStage.expandProgram([typed], []);
			final context = new BackendContext(outDir, null, "Main", true, false, HxDefineMap.fromRawDefines(["ocaml_profile=portable"]));
			new OcamlTargetCore().emit(program, context);

			final mainMlPath = findMainModulePath(outDir);
			final mainMl = File.getContent(mainMlPath);
			assertContains(mainMl, "HxBootArray.map (", "portable auto-metalization should use typed map lowering for metal-safe function");
			assertTrue(mainMl.indexOf("map_dyn") < 0, "portable auto-metalization test fixture should not emit map_dyn fallback");

			final report = readReport(outDir);
			assertTrue(report.schemaVersion == 1, "portable metalization report schemaVersion mismatch");
			assertTrue(report.profile == "portable", "portable metalization report profile mismatch");
			assertTrue(report.plannerMode == "portable_auto_metalization", "portable metalization planner mode mismatch");
			assertTrue(report.summary.totalRegions >= 4, "portable metalization report should include all Main functions");

			final metalSafeRegion = findRegion(report, "Main.metalSafeMap");
			assertTrue(metalSafeRegion.status == "auto_metalized", "metal-safe region should be auto-metalized");
			assertContains("\n" + metalSafeRegion.usedMetalStyleLowerings.join("\n") + "\n", "\narray_map_typed\n",
				"metal-safe region should report typed map lowering usage");

			final blockedRegion = findRegion(report, "Main.blocked");
			assertTrue(blockedRegion.status == "excluded", "reflection/dynamic region should be excluded");
			assertContains("\n" + blockedRegion.reasonCodes.join("\n") + "\n", "\ndynamic_type_hint\n",
				"blocked region should include dynamic-type exclusion reason");
			assertContains("\n" + blockedRegion.reasonCodes.join("\n") + "\n", "\nreflection_call\n",
				"blocked region should include reflection-call exclusion reason");
			assertTrue(blockedRegion.exclusionReasons.length >= 2, "blocked region should include explicit exclusion reasons");

			assertTrue(report.summary.excludedRegions >= 1, "portable metalization summary should include excluded regions");
			assertTrue(report.summary.usedMetalStyleRegions >= 1, "portable metalization summary should include used metal-style regions");
			assertContains("\n" + [for (entry in report.excludedByCode) entry.code].join("\n") + "\n", "\ndynamic_type_hint\n",
				"excluded-by-code summary should include dynamic_type_hint");
		} catch (error:haxe.Exception) {
			failure = error.message;
		} catch (message:String) {
			failure = message;
		}

		if (failure != null) {
			Sys.println("debug_out=" + tmpRoot);
			throw failure;
		}

		deleteRecursive(tmpRoot);
	}
}
