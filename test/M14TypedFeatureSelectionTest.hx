import sys.io.File;

/** Test branch rewriting with explicit decisions; discovery and DCE remain separate acceptance work. */
class M14TypedFeatureSelectionTest {
	static function main():Void {
		check("Main", ["probe.enabled"], "enabled\nbranch\nabsent\n");
		check("FeatureContract", [
			"probe.late",
			"probe.unused",
			"FeatureContract.active",
			"FeatureContract.*",
			"probe.value"
		],
			"late:on\ndefine:effect\nabsent:off\nunused:on\nmethod:on\nclass:on\nvalue:effect\nselected\ndefinition-value\nvalue:on\nactive:called\n");
		check("FeatureReachability", [
			"probe.nested",
			"probe.fallback",
			"probe.cycle.a",
			"probe.cycle.b",
			"probe.conditional"
		],
			"nested:on\nfallback:on\nfallback:effect\ncycle:b\ncycle:a\ncycle:on\nconditional:on\nmissing:off\n");
		rejectAbsentValue();
		check("FeatureFields", ["probe.field"], "field:effect\nselected\n");
		Sys.println("TYPED_FEATURE_SELECTION:PASS");
	}

	/** No value is fabricated for a two-argument selection whose feature is absent. */
	static function rejectAbsentValue():Void {
		final path = "test/fixtures/js_feature_intrinsic/FeatureAbsentValue.hx";
		final resolved = new ResolvedModule("FeatureAbsentValue", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final lowered = TypedFeatureSelection.lower(new MacroExpandedProgram([typed], false), []);
		var diagnostic = "";
		try {
			lowered.getTypedModules()[0].getBackendProjection();
		} catch (error:haxe.Exception) {
			diagnostic = error.message;
		}
		if (diagnostic != "statement control lowering requires an operand value")
			throw "absent feature value was accepted or failed at a different boundary: " + diagnostic;
	}

	/** Explicit decisions use the observed no-DCE contract; they are not discovery evidence. */
	static function check(module:String, decisions:Array<String>, expected:String):Void {
		final path = "test/fixtures/js_feature_intrinsic/" + module + ".hx";
		final resolved = new ResolvedModule(module, path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final source = new MacroExpandedProgram([typed], false);
		final revision = source.getTypedProgramRevision().getCanonicalIdentity();
		final lowered = TypedFeatureSelection.lower(source, decisions);
		if (lowered == source
			|| lowered.getTypedProgramRevision().getCanonicalIdentity() == revision
			|| CompilerTypedProgramRevision.fromTypedModules(source.getTypedModules(), source.macroMode).getCanonicalIdentity() != revision)
			throw "feature selection did not derive a distinct immutable revision";
		source.assertTypedBodyRevisionsCurrent();
		if (TypedFeatureSelection.lower(lowered, decisions) != lowered)
			throw "feature selection changed an already selected program";
		M14GenericConstructorArgumentTest.assertRuntime(lowered.getTypedModules()[0], module, expected);
		Sys.println("TYPED_FEATURE_SELECTION:" + module + ":PASS");
	}
}
