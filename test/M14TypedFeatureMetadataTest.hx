import haxe.io.Path;
import sys.io.File;

/** Metadata retention must match upstream, including removal of unused initializer effects under full DCE. */
class M14TypedFeatureMetadataTest {
	static function main():Void {
		final root = Path.normalize(Sys.getCwd() + "/test/fixtures/js_feature_intrinsic");
		final resolution = new CompilerSourceProvider().resolveModule([root], "FeatureMetadata");
		final path = resolution.filePath;
		if (path == null)
			throw "metadata fixture did not resolve";
		final resolved = new ResolvedModule("FeatureMetadata", path, ParserStage.parse(File.getContent(path), path), resolution.toOrigin("FeatureMetadata"));
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
			throw "metadata fixture requires one entry point";
		for (mode in ["std", "no", "full"]) {
			final roots = TypedFeatureRoots.select({
				program: program,
				sources: catalog,
				entryPoint: entries[0],
				mode: mode
			});
			final reachable = TypedFeatureMemberClosure.retain(roots);
			final features = new TypedFeatureDiscovery(reachable);
			final names = features.namesFor(program);
			for (name in [
				"metadata.init",
				"metadata.sub",
				"metadata.base",
				"metadata.exposed",
				"metadata.private",
				"MetadataInit.*"
			])
				if (names.indexOf(name) < 0)
					throw "metadata did not retain its feature: " + name;
			if ((names.indexOf("metadata.effect") >= 0) != (mode != "full")
				|| (names.indexOf("metadata.init-method") >= 0) != (mode != "full"))
				throw "metadata retained unused full-DCE declarations";
			Sys.println("TYPED_FEATURE_METADATA_DECISIONS:" + mode + ":PASS");
			final emission = new TypedEmissionRetention({reachable: reachable, mode: mode}).apply(program);
			final selected = TypedFeatureSelection.lower(emission, names);
			final expected = (mode == "full" ? "effect:off\ninit:on\ninit-method:off\n" : "field:effect\neffect:on\ninit:on\ninit-method:on\n")
				+ "sub:on\nbase:on\nexposed:on\nprivate:on\ninit-class:on\n";
			M14GenericConstructorArgumentTest.assertRuntime(selected.getTypedModules()[0], "FeatureMetadata", expected);
			Sys.println("TYPED_FEATURE_METADATA_RUNTIME:" + mode + ":PASS");
		}
		Sys.println("TYPED_FEATURE_METADATA:PASS");
	}
}
