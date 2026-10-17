import reflaxe.ocaml.tooling.ReflaxeOcamlInspection;

/** Runs the public inspection API once for valid output and each corrupted report. */
class VerifyInspection {
	static function main():Void {
		final args = Sys.args();
		final project = args.shift();
		if (project == null || args.length != 3)
			throw "Expected a project and three inspection directories";
		for (index in 0...args.length) {
			final report = ReflaxeOcamlInspection.inspect(project, args[index], true);
			final text = ReflaxeOcamlInspection.renderJson(report);
			if (index == 0) {
				if (!report.summary.valid)
					throw "Public inspection rejected valid output: " + text;
			} else {
				final expected = index == 1 ? "does not preserve its sealed" : "missing runtime requirement";
				if (report.summary.valid || text.indexOf(expected) < 0)
					throw "Public inspection did not reject the corrupted evidence as expected: " + text;
			}
		}
		Sys.println("DYNAMIC_ARRAY_BOOL_PLAN:PASS");
	}
}
