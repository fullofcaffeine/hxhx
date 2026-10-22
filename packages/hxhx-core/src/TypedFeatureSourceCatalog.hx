import haxe.io.Path;

/**
	Classify the selected sources of one typed program for feature discovery.
	Upstream treats unused SDK feature definitions differently from project definitions,
	including when the SDK was supplied as an explicit classpath. The configured SDK
	root and exact selected file determine this classification, not declaration names.

	This request-owned catalog does not change resolver identity or cache admission.
	It validates each selected classpath slot against the parsed source filename and
	stores only the resulting classification. Synthetic sources need an explicit
	source contract before they can participate in production feature discovery.
**/
class TypedFeatureSourceCatalog {
	final program:MacroExpandedProgram;
	final standardModules:haxe.ds.ObjectMap<TypedModule, Bool>;

	public function new(input:{program:MacroExpandedProgram, classPaths:Array<String>, standardRoot:String}) {
		program = input.program;
		program.assertTypedBodyRevisionsCurrent();
		standardModules = new haxe.ds.ObjectMap<TypedModule, Bool>();
		final standard = absolute(input.standardRoot);
		final roots = input.classPaths.map(absolute);
		for (module in program.getTypedModules()) {
			final origin = module.getSourceOrigin();
			if (origin.isSynthetic)
				throw "feature source classification requires a resolved module origin";
			if (origin.selectedClassPathIndex >= roots.length)
				throw "feature source classification has no selected classpath slot";
			final selected = Path.normalize(Path.join([
				roots[origin.selectedClassPathIndex],
				origin.sourceModulePath.split(".").join("/") + ".hx"
			]));
			if (selected != absolute(module.getParsed().getFilePath()))
				throw "feature source classification does not match the selected source file";
			final prefix = StringTools.endsWith(standard, "/") ? standard : standard + "/";
			standardModules.set(module, StringTools.startsWith(selected, prefix));
		}
	}

	/** Reject decisions reused with another program or an equal-looking module copy. */
	public function isStandardLibrary(owner:MacroExpandedProgram, module:TypedModule):Bool {
		if (owner != program)
			throw "feature source catalog belongs to another typed program";
		if (!standardModules.exists(module))
			throw "feature source catalog does not own this typed module";
		return standardModules.get(module);
	}

	/** Configuration must already be resolved for this request; never consult process cwd here. */
	static function absolute(path:String):String {
		if (path == null || !Path.isAbsolute(path))
			throw "feature source classification requires absolute configured paths";
		return Path.normalize(path);
	}
}
