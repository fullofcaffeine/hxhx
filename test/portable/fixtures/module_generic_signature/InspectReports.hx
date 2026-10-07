import reflaxe.ocaml.tooling.ReflaxeOcamlInspection;

/** Checks valid output and independent corrupted copies with one inspector compilation. */
class InspectReports {
	static function main():Void {
		final args = Sys.args();
		final project = args.shift();
		if (project == null || args.length == 0)
			throw "Expected a project and at least one output directory";
		final reports = [];
		for (output in args) {
			final started = haxe.Timer.stamp();
			final cpuStarted = Sys.cpuTime();
			Sys.stderr().writeString('Inspecting ${haxe.io.Path.withoutDirectory(output)}\n');
			Sys.stderr().flush();
			reports.push(ReflaxeOcamlInspection.inspect(project, output, true));
			Sys.stderr()
				.writeString('Inspected ${haxe.io.Path.withoutDirectory(output)}: ${Math.round((haxe.Timer.stamp() - started) * 1000)} ms wall, ${Math.round((Sys.cpuTime() - cpuStarted) * 1000)} ms CPU\n');
			Sys.stderr().flush();
		}
		Sys.println(haxe.Json.stringify(reports));
	}
}
