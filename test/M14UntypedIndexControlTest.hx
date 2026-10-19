/** Compare unchecked indexed writes with upstream execution and retain precise address storage. */
class M14UntypedIndexControlTest {
	static function main():Void {
		final source = sys.io.File.getContent("test/fixtures/untyped_index_control/Main.hx");
		final output = JsRuntimeFixture.reserveOutput();
		sys.io.File.saveContent(output + "/Main.hx", source);
		@:privateAccess M14JsFunctionLiteralRuntimeTest.command("haxe", ["-cp", output, "-main", "Main", "-js", output + "/upstream.js"]);
		@:privateAccess M14JsFunctionLiteralRuntimeTest.command("node", [output + "/upstream.js"]);
		Sys.println("UNTYPED_INDEX_CONTROL_UPSTREAM:PASS");
		final program = JsSourceProgramFixture.build({
			sources: [{path: "Main.hx", source: source}],
			requiredModules: ["Array"]
		});
		final functions = [
			for (module in program.getTypedModules())
				for (owner in module.getTypedClasses())
					if (owner.getSemanticInfo().getIdentity().getCanonicalName() == "Main")
						for (fn in owner.getFunctions())
							fn
		];
		for (fn in functions) {
			final revision = CompilerTypedTreeRevision.functionBody(fn);
			final lowered = TypedControlLowering.functionBody(fn);
			if (revision != CompilerTypedTreeRevision.functionBody(fn))
				throw "address lowering changed typed source";
			if (CompilerTypedTreeRevision.functionBody(lowered) != CompilerTypedTreeRevision.functionBody(TypedControlLowering.functionBody(lowered)))
				throw "address lowering changed on repeated application";
		}
		JsRuntimeFixture.assertProgramRuntime(program, "Main", "");
		@:privateAccess JsRuntimeFixture.removeOutput(output);
		assertIncompleteStorageRejected();
		Sys.println("UNTYPED_INDEX_CONTROL:PASS");
	}

	/** An unchecked use grants no storage type when the enclosed foreign value is also unresolved. */
	static function assertIncompleteStorageRejected():Void {
		final text = 'abstract Handle(Dynamic){}class Main{static function main():Void{'
			+ 'var values=[1];var handle:Handle=cast {};values[untyped handle.missing]={var result=2;result;};}}';
		final output = JsRuntimeFixture.reserveOutput();
		sys.io.File.saveContent(output + "/Main.hx", text);
		@:privateAccess M14JsFunctionLiteralRuntimeTest.command("haxe", ["-cp", output, "-main", "Main", "-js", output + "/upstream.js"]);
		final resolved = new ResolvedModule("Main", output + "/Main.hx", ParserStage.parse(text, output + "/Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		var rejected = false;
		try {
			typed.getBackendProjection();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf("control-valued assignment requires complete address operand types") < 0)
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "unresolved foreign index acquired invented storage";
		@:privateAccess JsRuntimeFixture.removeOutput(output);
		Sys.println("UNTYPED_INDEX_INCOMPLETE_STORAGE:PASS");
	}
}
