import reflaxe.ocaml.tooling.ReflaxeOcamlInspection;

/** Compiles the public inspector once for independent exception-evidence copies. */
class InspectReports {
	static function main():Void {
		final args = Sys.args();
		final project = args.shift();
		if (project == null || args.length == 0)
			throw "Expected a project and at least one output directory";
		final reports = [for (output in args) ReflaxeOcamlInspection.inspect(project, output, true)];
		Sys.println(haxe.Json.stringify(reports));
	}
}
