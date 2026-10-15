import sys.io.File;

/** Invalid authored protocols must produce source diagnostics, never typed-replay crashes. */
class M14KeyValueProtocolDiagnosticsTest {
	public static function run():Void {
		final cases = [
			{
				label: "scalar",
				iterable: "1",
				members: null,
				diagnostic: "keyValueIterator",
				candidateDiagnostic: "protocol"
			},
			{
				label: "missing-next",
				iterable: "new Cursor()",
				members: "public function hasNext():Bool return false;",
				diagnostic: "next",
				candidateDiagnostic: "has no field next"
			},
			{
				label: "non-bool-condition",
				iterable: "new Cursor()",
				members: 'public function hasNext():String return "no"; public function next():{key:Int,value:Int} return {key:0,value:1};',
				diagnostic: "Bool",
				candidateDiagnostic: "protocol"
			},
			{
				label: "missing-value",
				iterable: "new Cursor()",
				members: "public function hasNext():Bool return false; public function next():{key:Int} return {key:0};",
				diagnostic: "value",
				candidateDiagnostic: "resolved iterator protocol"
			}
		];
		for (item in cases) {
			final output = JsRuntimeFixture.reserveOutput();
			final path = output + "/Main.hx";
			final source = "class Main {\nstatic function main():Void {\nfor (key => value in "
				+ item.iterable
				+ ") {}\n}\n}\n"
				+ (item.members == null ? "" : "class Cursor { public function new() {} public function keyValueIterator():Cursor return this; "
					+ item.members
					+ " }");
			File.saveContent(path, source);
			final configured = Sys.getEnv("HXHX_UPSTREAM_HAXE");
			final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", [
				"20",
				configured == null ? "node_modules/.bin/haxe" : configured,
				"-cp",
				output,
				"-main",
				"Main",
				"-js",
				output + "/main.js"
			]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code == 0 || code == 124 || stderr.indexOf(item.diagnostic) < 0)
				throw item.label + ": upstream did not report the expected protocol error: " + stdout + stderr;
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			var rejected = false;
			try {
				TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			} catch (error:TyperError) {
				if (error.filePath != path || error.pos.line != 3 || error.message.indexOf(item.candidateDiagnostic) < 0)
					throw item.label + ": inaccurate protocol diagnostic: " + error.toString();
				rejected = true;
			}
			if (!rejected)
				throw item.label + ": invalid key/value protocol was accepted";
			@:privateAccess JsRuntimeFixture.removeOutput(output);
		}
		Sys.println("KEY_VALUE_PROTOCOL_DIAGNOSTICS:PASS");
	}

	static function main():Void {
		run();
	}
}
