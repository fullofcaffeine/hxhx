import sys.io.File;

/** All-retained component checks derive decisions from owned declarations instead of fixture-supplied feature names. */
class M14TypedFeatureDiscoveryTest {
	static function load(module:String):MacroExpandedProgram {
		final path = "test/fixtures/js_feature_intrinsic/" + module + ".hx";
		final resolved = new ResolvedModule(module, path, ParserStage.parse(File.getContent(path), path));
		return new MacroExpandedProgram([TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]))], false);
	}

	static function check(module:String, expected:String):Void {
		final source = load(module);
		final discovered = TypedFeatureDiscovery.allRetained(source);
		final lowered = TypedFeatureSelection.lower(source, discovered.namesFor(source));
		if (module == "FeatureShadowing" && lowered != source)
			throw "discovery or selection rewrote ordinary shadowing declarations";
		M14GenericConstructorArgumentTest.assertRuntime(lowered.getTypedModules()[0], module, expected);
		Sys.println("TYPED_FEATURE_DISCOVERY:" + module + ":PASS");
	}

	static function main():Void {
		check("Main", "enabled\nbranch\nabsent\n");
		check("FeatureContract",
			"late:on\ndefine:effect\nabsent:off\nunused:on\nmethod:on\nclass:on\nvalue:effect\nselected\ndefinition-value\nvalue:on\nactive:called\n");
		check("FeatureReachability", "nested:on\nfallback:on\nfallback:effect\ncycle:b\ncycle:a\ncycle:on\nconditional:on\nmissing:off\n");
		check("FeatureNames", "module:off\nshort:on\nmodule-class:off\nshort-class:on\ntouch\n");
		ownership();
		Sys.println("TYPED_FEATURE_DISCOVERY_OWNERSHIP:PASS");
		check("FeatureShadowing", "local:probe.shadow:yes:no\nmethod:probe.method:value\n");
		Sys.println("TYPED_FEATURE_DISCOVERY:PASS");
	}

	/** Retention inputs are physical declarations, and decisions never transfer to another program. */
	static function ownership():Void {
		final source = load("FeatureContract");
		final classes = source.getTypedModules()[0].getTypedClasses();
		final functions = [for (owner in classes) for (fn in owner.getFunctions()) fn];
		final retained = functions.filter(fn -> fn.getDeclaration().getSignature().getName() != "unused");
		final subset = new TypedFeatureDiscovery({
			program: source,
			classes: classes,
			functions: retained,
			fields: []
		});
		if (subset.namesFor(source).indexOf("probe.unused") >= 0)
			throw "discovery scanned a function excluded by the retention owner";
		final reversed = retained.copy();
		reversed.reverse();
		final reordered = new TypedFeatureDiscovery({
			program: source,
			classes: classes,
			functions: reversed,
			fields: []
		});
		if (subset.namesFor(source).join(";") != reordered.namesFor(source).join(";"))
			throw "feature discovery depends on retained declaration order";
		final names = subset.namesFor(source);
		names.push("forged");
		if (subset.namesFor(source).indexOf("forged") >= 0)
			throw "feature discovery exposed mutable decisions";
		reject(() -> subset.namesFor(new MacroExpandedProgram(source.getTypedModules(), false)), "feature discovery belongs to another typed program");
		final fn = functions[0];
		reject(() -> new TypedFeatureDiscovery({
			program: source,
			classes: classes,
			functions: [fn.withBody(fn.getBody())],
			fields: []
		}), "retained feature function is not an exact declaration of a retained class");
		final foreign = load("FeatureContract").getTypedModules()[0].getTypedClasses()[0];
		reject(() -> new TypedFeatureDiscovery({
			program: source,
			classes: [foreign],
			functions: [],
			fields: []
		}), "retained feature class is not an exact semantic provider in this program");
	}

	static function reject(action:Void->Void, expected:String):Void {
		var diagnostic = "";
		try {
			action();
		} catch (error:haxe.Exception) {
			diagnostic = error.message;
		}
		if (diagnostic != expected)
			throw "feature ownership rejection differs: " + diagnostic;
	}
}
