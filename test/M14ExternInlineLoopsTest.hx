/** Required inline loop bodies must preserve exact control destinations and runtime effects. */
class M14ExternInlineLoopsTest {
	static function main():Void {
		final source = sys.io.File.getContent("test/fixtures/extern_inline_loops/Main.hx");
		@:privateAccess M14MultiTypeRuntimeTest.run("extern_inline_loops", source);
		for (loop in [
			"for (i in 0...n) { if (i == 2) return i; }",
			"var i=0; while (i<n) { if(i==2) return i; i++; }"
		])
			rejectNonFinalReturn(loop);
		Sys.println("EXTERN_INLINE_LOOPS:PASS");
	}

	/** Upstream rejects an early return from a required inline loop; it must never exit the caller. */
	static function rejectNonFinalReturn(loop:String):Void {
		final source = 'class Main { static extern inline function take(n:Int):Int {'
			+ loop
			+ 'return -1;} static function main():Void { var result=take(5); } }';
		final output = JsRuntimeFixture.reserveOutput();
		sys.io.File.saveContent(output + "/Main.hx", source);
		final process = new sys.io.Process("haxe", ["-cp", output, "-main", "Main", "-js", output + "/upstream.js"]);
		final stdout = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code == 0 || errors.indexOf("Cannot inline a not final return") < 0)
			throw "upstream inline return contract changed: " + stdout + errors;
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final index = TyperIndex.build([resolved]);
		var rejected = false;
		try {
			final typed = TyperStage.typeResolvedModule(resolved, index);
			TypedRequiredInlineLowering.lowerClasses(typed.getTypedClasses(), index);
		} catch (message:String) {
			rejected = message.indexOf("Cannot inline a not final return") >= 0;
		}
		if (!rejected)
			throw "required inline admitted a non-final loop return";
		@:privateAccess JsRuntimeFixture.removeOutput(output);
	}
}
