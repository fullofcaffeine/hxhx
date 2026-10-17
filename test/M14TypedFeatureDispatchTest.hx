import haxe.io.Path;
import sys.io.File;

/** Parent/interface retention must include reachable implementations while excluding unrelated names. */
class M14TypedFeatureDispatchTest {
	static function main():Void {
		final root = Path.normalize(Sys.getCwd() + "/test/fixtures/js_feature_intrinsic");
		final source = new CompilerSourceProvider();
		final resolution = source.resolveModule([root], "FeatureDispatch");
		final path = resolution.filePath;
		if (path == null)
			throw "dispatch feature fixture did not resolve";
		final resolved = new ResolvedModule("FeatureDispatch", path, ParserStage.parse(File.getContent(path), path), resolution.toOrigin("FeatureDispatch"));
		final module = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new MacroExpandedProgram([module], false);
		final catalog = new TypedFeatureSourceCatalog({program: program, classPaths: [root], standardRoot: root + "/origin_lib"});
		final entries = [
			for (owner in module.getTypedClasses())
				for (fn in owner.getFunctions())
					if (fn.getDeclaration().getSignature().getName() == "main")
						fn
		];
		if (entries.length != 1)
			throw "dispatch feature fixture requires one entry point";
		for (mode in ["full", "std", "no"]) {
			final roots = TypedFeatureRoots.select({
				program: program,
				sources: catalog,
				entryPoint: entries[0],
				mode: mode
			});
			final features = TypedFeatureMemberClosure.discover(roots);
			final selected = TypedFeatureSelection.lower(program, features.namesFor(program));
			M14GenericConstructorArgumentTest.assertRuntime(selected.getTypedModules()[0], "FeatureDispatch",
				"parent:on\nchild:on\nclass-only:on\n"
				+ (mode == "full" ? "unused:off\n" : "unused:on\n")
				+ "interface:on\n"
				+ (mode == "full" ? "unrelated:off\n" : "unrelated:on\n")
				+ "follow:on\nchild:called\ninterface:called\ntrue\ntrue\n");
			Sys.println("TYPED_FEATURE_DISPATCH:" + mode + ":PASS");
		}
		Sys.println("TYPED_FEATURE_DISPATCH:PASS");
	}
}
