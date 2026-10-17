import sys.io.File;

/** Value iteration preserves selected protocol effects and source loop destinations. */
class M14ValueIteratorProtocolTest {
	static function main():Void {
		final root = "test/fixtures/value_iterator_protocol";
		final output = JsRuntimeFixture.reserveOutput();
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command("haxe", ["-cp", root, "-main", "Main", "-js", output + "/upstream.js"]);
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command("node", [output + "/upstream.js"]);
		Sys.println("VALUE_ITERATOR_PROTOCOL_UPSTREAM:PASS");
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		JsRuntimeFixture.assertRuntime(typed, "Main", "");
		@:privateAccess JsRuntimeFixture.removeOutput(output);
		Sys.println("VALUE_ITERATOR_PROTOCOL_RUNTIME:PASS");
		for (entry in [
			{
				label: "scalar",
				source: "class Main {static function main():Void {for (value in 1) {}}}",
				upstream: "iterator",
				local: "Int has no field iterator"
			},
			{
				label: "condition",
				source: "class Main {static function main():Void {for (value in new Cursor()) {}}}" +
				"class Cursor {public function new() {} public function iterator():Cursor return this;" +
				'public function hasNext():String return "bad"; public function next():Int return 1;}',
				upstream: "Bool",
				local: "protocol"
			}
		]) {
			final output = JsRuntimeFixture.reserveOutput();
			final path = output + "/Main.hx";
			File.saveContent(path, entry.source);
			final process = new sys.io.Process("haxe", ["-cp", output, "-main", "Main", "-js", output + "/upstream.js"]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code == 0 || stderr.indexOf(entry.upstream) < 0)
				throw entry.label + ": upstream accepted an invalid iterator: " + stdout + stderr;
			final module = new ResolvedModule("Main", path, ParserStage.parse(entry.source, path));
			var rejected = false;
			try {
				TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			} catch (error:TyperError) {
				if (error.filePath != path || error.message.indexOf(entry.local) < 0)
					throw error;
				rejected = true;
			}
			if (!rejected)
				throw entry.label + ": native typing accepted an invalid iterator";
			@:privateAccess JsRuntimeFixture.removeOutput(output);
		}
		Sys.println("VALUE_ITERATOR_PROTOCOL_DIAGNOSTICS:PASS");
	}
}
