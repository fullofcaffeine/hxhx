package hxhx;

/**
	Complete JS feature selection before a backend can project typed bodies.
	The driver supplies the exact resolver paths and SDK root for this request;
	neither backend selection nor an emitter may reconstruct source provenance.
	The returned program carries both retained declarations and runtime binding
	features, so builtin and promoted JS providers receive the same decisions.
**/
class Stage3JsPreparation {
	/** Resolve a present main to its owned declaration; libraries use only the existing mode and keep roots. */
	public static function prepare(input:{
		program:MacroExpandedProgram,
		classPaths:Array<String>,
		standardRoot:String,
		main:Null<String>,
		defines:haxe.ds.StringMap<String>
	}):MacroExpandedProgram {
		final sources = new TypedFeatureSourceCatalog({
			program: input.program,
			classPaths: input.classPaths,
			standardRoot: input.standardRoot
		});
		var entry:Null<TypedFunction> = null;
		if (input.main != null && input.main.length > 0) {
			for (module in input.program.getTypedModules()) {
				if (module.getSourceOrigin().sourceModulePath != input.main)
					continue;
				final mainClass = HxModuleDecl.getMainClass(module.getParsed().getDecl());
				for (owner in module.getTypedClasses()) {
					if (owner.getSourceDeclaration() != mainClass)
						continue;
					for (fn in owner.getFunctions()) {
						final declaration = fn.getSourceDeclaration();
						if (HxFunctionDecl.getName(declaration) != "main" || !HxFunctionDecl.getIsStatic(declaration))
							continue;
						if (entry != null)
							throw "JS preparation requires one exact main function";
						entry = fn;
					}
				}
			}
			if (entry == null)
				throw "JS preparation could not find the selected main function";
		}
		final configuredMode = input.defines.get("dce");
		// Haxe 4.3.7's omitted DCE option has the same contract as explicit std.
		final mode = configuredMode == null ? "std" : configuredMode;
		final roots = TypedFeatureRoots.select({
			program: input.program,
			sources: sources,
			entryPoint: entry,
			mode: mode
		});
		final reachable = TypedFeatureMemberClosure.retain(roots);
		final features = new TypedFeatureDiscovery(reachable);
		final retained = new TypedEmissionRetention({reachable: reachable, mode: mode}).apply(input.program);
		return TypedFeatureSelection.lower(retained, features.namesFor(input.program));
	}
}
