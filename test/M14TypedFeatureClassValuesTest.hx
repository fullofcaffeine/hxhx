import haxe.io.Path;
import sys.io.File;

/** Feature traversal uses resolved class and inheritance identities, not short source names. */
class M14TypedFeatureClassValuesTest {
	static function main():Void {
		final root = Path.normalize(Sys.getCwd() + "/test/fixtures/js_feature_intrinsic");
		final source = new CompilerSourceProvider();
		final resolution = source.resolveModule([root], "FeatureClassValues");
		final path = resolution.filePath;
		if (path == null)
			throw "class feature fixture did not resolve";
		final resolved = new ResolvedModule("FeatureClassValues", path, ParserStage.parse(File.getContent(path), path),
			resolution.toOrigin("FeatureClassValues"));
		final module = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new MacroExpandedProgram([module], false);
		for (mode in ["full", "std", "no"]) {
			final features = discover(program, root, mode);
			final selected = TypedFeatureSelection.lower(program, features.namesFor(program));
			M14GenericConstructorArgumentTest.assertRuntime(selected.getTypedModules()[0], "FeatureClassValues",
				"child:on\nparent:on\ninterface:on\nchild-init:on\nparent-init:on\n" + (mode == "full" ? "unused:off\n" : "unused:on\n") + "true\n");
			Sys.println("TYPED_FEATURE_CLASS_VALUES:" + mode + ":PASS");
		}
		final missing = module.withTypedClasses(module.getTypedClasses().filter(owner -> owner.getSemanticInfo().getShortName() != "ClassParent"));
		var diagnostic = "";
		try {
			discover(new MacroExpandedProgram([missing], false), root, "full");
		} catch (error:haxe.Exception) {
			diagnostic = error.message;
		}
		if (diagnostic != "feature class reference has no exact program provider: FeatureClassValues.ClassParent")
			throw "missing feature parent was not rejected: " + diagnostic;
		Sys.println("TYPED_FEATURE_CLASS_VALUES:PASS");
	}

	static function discover(program:MacroExpandedProgram, root:String, mode:String):TypedFeatureDiscovery {
		final catalog = new TypedFeatureSourceCatalog({program: program, classPaths: [root], standardRoot: root + "/origin_lib"});
		final entries = [
			for (module in program.getTypedModules())
				for (owner in module.getTypedClasses())
					for (fn in owner.getFunctions())
						if (fn.getDeclaration().getSignature().getName() == "main")
							fn
		];
		if (entries.length != 1)
			throw "class feature fixture requires one entry point";
		return TypedFeatureMemberClosure.discover(TypedFeatureRoots.select({
			program: program,
			sources: catalog,
			entryPoint: entries[0],
			mode: mode
		}));
	}
}
