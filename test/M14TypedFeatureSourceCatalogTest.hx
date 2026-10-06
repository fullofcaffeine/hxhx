import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Feature policy must follow the actual selected SDK source, including overrides and secondary types. */
class M14TypedFeatureSourceCatalogTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function main():Void {
		final root = Path.normalize(Sys.getCwd() + "/.tmp/feature_source_" + Date.now().getTime());
		final standard = root + "/std";
		final project = root + "/std-project";
		final target = standard + "/js/_std";
		for (directory in [standard, project, target]) {
			FileSystem.createDirectory(directory);
			File.saveContent(directory + "/Probe.hx", "class Probe {} class Secondary {}\n");
		}
		function check(paths:Array<String>, lookup:String, expected:Bool):Void {
			final source = new CompilerSourceProvider();
			final resolution = source.resolveModule(paths, lookup);
			require(resolution.filePath != null, "fixture must resolve a real selected source");
			final parsed = ParserStage.parse(File.getContent(resolution.filePath), resolution.filePath);
			final resolved = new ResolvedModule("Probe", resolution.filePath, parsed, resolution.toOrigin(lookup));
			final module = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
			final program = new MacroExpandedProgram([module], false);
			final catalog = new TypedFeatureSourceCatalog({program: program, classPaths: paths, standardRoot: standard + "/."});
			require(catalog.isStandardLibrary(program, module) == expected, "feature source classification differs: " + lookup);
			final copied = module.withTypedClasses(module.getTypedClasses());
			reject(() -> catalog.isStandardLibrary(program, copied), "feature source catalog does not own this typed module");
			reject(() -> catalog.isStandardLibrary(new MacroExpandedProgram([module], false), module),
				"feature source catalog belongs to another typed program");
			final alteredPaths = paths.copy();
			alteredPaths[resolution.selectedClassPathIndex] = root + "/foreign";
			reject(() -> new TypedFeatureSourceCatalog({program: program, classPaths: alteredPaths, standardRoot: standard}),
				"feature source classification does not match the selected source file");
			reject(() -> new TypedFeatureSourceCatalog({program: program, classPaths: [], standardRoot: standard}),
				"feature source classification has no selected classpath slot");
			reject(() -> new TypedFeatureSourceCatalog({program: program, classPaths: paths, standardRoot: "std"}),
				"feature source classification requires absolute configured paths");
			// Mutating the caller's path array must not change a completed decision.
			paths[resolution.selectedClassPathIndex] = root + "/foreign";
			require(catalog.isStandardLibrary(program, module) == expected, "feature catalog retained mutable configuration");
		}
		check([project, target, standard], "Probe", false);
		check([target, standard], "Probe", true);
		check([standard + "/.", target], "Probe", true);
		check([root + "/missing", standard], "Probe.Secondary", true);
		check([project, standard], "Probe.Secondary", false);
		final syntheticParsed = ParserStage.parse("class Synthetic {}", root + "/Synthetic.hx");
		final synthetic = new ResolvedModule("Synthetic", root + "/Synthetic.hx", syntheticParsed);
		final syntheticProgram = new MacroExpandedProgram([TyperStage.typeResolvedModule(synthetic, TyperIndex.build([synthetic]))], false);
		reject(() -> new TypedFeatureSourceCatalog({program: syntheticProgram, classPaths: [root], standardRoot: standard}),
			"feature source classification requires a resolved module origin");
		removeTree(root);
		Sys.println("TYPED_FEATURE_SOURCE_CATALOG:PASS");
	}

	static function reject(action:Void->Void, expected:String):Void {
		var diagnostic = "";
		try {
			action();
		} catch (error:haxe.Exception) {
			diagnostic = error.message;
		}
		require(diagnostic == expected, "feature source rejection differs: " + diagnostic);
	}

	/** Remove only the directory allocated by this fixture. */
	static function removeTree(path:String):Void {
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				removeTree(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else
			FileSystem.deleteFile(path);
	}
}
