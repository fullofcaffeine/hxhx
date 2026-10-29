import sys.io.File;

/** Compare optional-bound calls with upstream and reject copied call markers. */
class M14Stage3OptionalBoundsTest {
	static final root = "test/fixtures/stage3_optional_bounds";

	static function assertOwnership(typed:TypedModule):Void {
		var checked = 0;
		for (owner in typed.getBackendProjection().getClasses())
			for (fn in owner.getFunctions())
				for (statement in fn.getBody())
					TypedBackendSourceWalk.statement(statement, expression -> {
						final call = TypedExactCallSource.decodeInstance(expression);
						if (call == null || (call.owner != "String" && call.owner != "Array"))
							return;
						final occurrence = fn.findInstanceCall(expression);
						if (occurrence == null)
							throw "bounds call lost its typed occurrence";
						final copied = TypedExactCallSource.encodeInstance(call.owner, call.declaration, call.method, call.resultType, call.receiver,
							call.arguments);
						if (fn.findInstanceCall(copied) != null)
							throw "copied bounds call borrowed an occurrence";
						var foreignRejected = false;
						try
							occurrence.assertCurrent("another executable", "another revision")
						catch (error:Dynamic) {
							foreignRejected = Std.string(error) == "instance call belongs to another executable or revision";
						}
						if (!foreignRejected)
							throw "bounds call accepted another executable owner";
						switch expression {
							case ECall(_, payload):
								final original = payload[5];
								payload[5] = EString("changed argument");
								var mutationRejected = false;
								try
									occurrence.getCall()
								catch (error:Dynamic) {
									mutationRejected = Std.string(error) == "instance call marker was mutated";
								}
								payload[5] = original;
								if (!mutationRejected)
									throw "bounds call accepted a mutated operand";
								occurrence.getCall();
							case _: throw "bounds call lost its marker";
						}
						checked++;
					}, _ -> {});
		if (checked < 28)
			throw "bounds ownership coverage is incomplete: " + checked;
	}

	static function main():Void {
		final expected = "rabrabrarabounds:ok\n";
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		final path = root + "/Main.hx";
		final typed = M14Stage3RuntimeFixture.typeMain({source: File.getContent(path), path: path, root: root});
		assertOwnership(typed);
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), ".tmp/stage3-optional-bounds");
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("STAGE3_OPTIONAL_BOUNDS:PASS");
	}
}
