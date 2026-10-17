import sys.io.File;

/** Observe structural calls after ordinary full declaration retention. */
class M14StructuralMethodRetentionTest {
	static function main():Void {
		final root = "test/fixtures/structural_method_retention";
		final output = JsRuntimeFixture.reserveOutput();
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command("haxe", ["-cp", root, "-main", "Main", "-dce", "full", "-js", output
			+ "/upstream.js"]);
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command("node", [output + "/upstream.js"]);
		Sys.println("STRUCTURAL_METHOD_RETENTION_UPSTREAM:PASS");
		final path = root + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final index = TyperIndex.build([resolved]);
		final module = TyperStage.typeResolvedModule(resolved, index);
		final program = new MacroExpandedProgram([module], false);
		for (owner in module.getTypedClasses())
			for (fn in owner.getFunctions())
				if (fn.getDeclaration().getSignature().getName() == "provide" && !fn.getEnvironment().getReturnType().isAnonymous())
					throw "structural retention fixture requires a resolved record result";
		final entries = [
			for (owner in module.getTypedClasses())
				for (fn in owner.getFunctions())
					if (fn.getDeclaration().getOwner().getCanonicalName() == "Main"
						&& fn.getDeclaration().getSignature().getName() == "main")
						fn
		];
		if (entries.length != 1)
			throw "structural method fixture requires one exact entry";
		final reachable = TypedFeatureMemberClosure.retain({
			program: program,
			classes: [],
			functions: entries,
			fields: []
		});
		for (fn in reachable.functions)
			if (fn.getDeclaration().getOwner().getCanonicalName() == "Main.Unrelated"
				&& fn.getDeclaration().getSignature().getName() != "new")
				throw "structural retention reached an unrelated implementation";
		final features = new TypedFeatureDiscovery(reachable);
		final retained = TypedFeatureSelection.lower(new TypedEmissionRetention({reachable: reachable, mode: "full"}).apply(program),
			features.namesFor(program));
		JsRuntimeFixture.assertProgramRuntime(retained, "Main", "");
		@:privateAccess JsRuntimeFixture.removeOutput(output);
		Sys.println("STRUCTURAL_METHOD_RETENTION_RUNTIME:PASS");
	}
}
