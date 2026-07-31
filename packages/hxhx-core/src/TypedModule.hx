/**
	One immutable typed module revision.

	Parsed declarations remain available for imports, metadata, and diagnostics.
	`sourceOrigin` carries path-safe compiler provenance separately. Function-body
	semantics live in `typedClasses`; backends
	must not re-read bodies through `getParsed()`. A module is sealed at
	construction and rejects parsed-body mutation until it is retyped as a new
	revision.
**/
class TypedModule {
	final parsed:ParsedModule;
	final env:TyModuleEnv;
	final typedClasses:Array<TypedClass>;
	final revision:Int;
	final sourceOrigin:CompilerModuleOrigin;
	final conditionalCompilation:CompilerConditionalCompilationObservation;
	final generatedDeclarations:CompilerGeneratedDeclarationObservation;
	final backendDeclarationCatalog:TypedBackendDeclarationCatalog;
	final backendDeclaration:HxModuleDecl;

	public function new(parsed:ParsedModule, env:TyModuleEnv, ?typedClasses:Array<TypedClass>, revision:Int = 1, ?sourceOrigin:CompilerModuleOrigin,
			?conditionalCompilation:CompilerConditionalCompilationObservation, ?generatedDeclarations:CompilerGeneratedDeclarationObservation) {
		this.parsed = parsed;
		this.env = env;
		this.typedClasses = (typedClasses == null ? TypedBodyBuilder.buildFallbackModule(parsed, env) : typedClasses).copy();
		this.revision = revision <= 0 ? 1 : revision;
		this.sourceOrigin = sourceOrigin == null ? syntheticSourceOrigin(parsed) : sourceOrigin;
		this.conditionalCompilation = conditionalCompilation == null ? CompilerConditionalCompilationObservation.empty() : conditionalCompilation;
		this.generatedDeclarations = generatedDeclarations == null ? CompilerGeneratedDeclarationObservation.empty() : generatedDeclarations;
		TypedBodyInvariant.assertClasses(this.typedClasses);
		this.backendDeclarationCatalog = TypedBodySource.moduleDeclarationCatalog(parsed, this.typedClasses);
		this.backendDeclaration = backendDeclarationCatalog.getDeclaration();
	}

	public function getParsed():ParsedModule {
		return parsed;
	}

	public function getEnv():TyModuleEnv {
		return env;
	}

	public function getTypedClasses():Array<TypedClass> {
		return typedClasses.copy();
	}

	public function getRevision():Int {
		return revision;
	}

	/** Return the path-safe source origin selected before this module was typed. **/
	public function getSourceOrigin():CompilerModuleOrigin
		return sourceOrigin;

	/** Compile-time `#if` choices that produced this typed module's parsed input. **/
	public function getConditionalCompilation():CompilerConditionalCompilationObservation
		return conditionalCompilation;

	/** One-way identity of declarations produced by build macros before typing. **/
	public function getGeneratedDeclarations():CompilerGeneratedDeclarationObservation
		return generatedDeclarations;

	/** Return the next immutable semantic revision after a shared typed-body pass. **/
	public function withTypedClasses(classes:Array<TypedClass>):TypedModule {
		return new TypedModule(parsed, env, classes, revision + 1, sourceOrigin, conditionalCompilation, generatedDeclarations);
	}

	/**
		Return the declaration/signature projection whose bodies come exclusively
		from the structural typed tree.

		This is the one-cutover adapter for source-shaped emitters. It must not be
		used by typing or macros, and it never re-reads parsed function bodies. The
		legacy source AST uses mutable arrays, so backends must treat this cached
		projection as read-only; it is not semantic storage and cannot mutate the
		structural typed body.
	**/
	public function getBackendDeclaration():HxModuleDecl {
		return backendDeclaration;
	}

	/**
		Return the source-shaped backend migration view together with the exact
		typed-local and bare field-read catalogs used to project every function
		body.

		Build this stricter view only when a migrated backend requests it. Legacy
		backends keep the declaration-only compatibility path and cannot be
		rejected by projection rules they do not yet consume.
	**/
	public function getBackendProjection():TypedBackendModuleProjection
		return TypedBodySource.moduleProjection(parsed, typedClasses);

	/**
		Pair one declaration selected through the legacy backend view with the
		strict projection built from the same sealed typed module.

		Only `TypedModule` owns both views. The legacy declaration catalog resolves
		the exact objects to a stable typed identity, which selects the strict
		projection without exposing parsed source or asking a target to guess from
		names or traversal order.
	**/
	public function findBackendFunctionProjection(backendClass:HxClassDecl, backendFunction:HxFunctionDecl):Null<{
		module:TypedBackendModuleProjection,
		classProjection:TypedBackendClassProjection,
		functionProjection:TypedBackendFunctionProjection
	}> {
		final stableIdentity = backendDeclarationCatalog.findFunctionIdentity(backendClass, backendFunction);
		if (stableIdentity == null)
			return null;
		final moduleProjection = getBackendProjection();
		var selectedClass:Null<TypedBackendClassProjection> = null;
		var selected:Null<TypedBackendFunctionProjection> = null;
		for (projectedClass in moduleProjection.getClasses())
			for (projectedFunction in projectedClass.getFunctions())
				if (projectedFunction.getStableIdentity() == stableIdentity) {
					if (selected != null)
						throw "typed backend projection contains duplicate stable function identity " + stableIdentity;
					selectedClass = projectedClass;
					selected = projectedFunction;
				}
		if (selected == null)
			throw "typed backend projection lost stable function identity " + stableIdentity;
		return {module: moduleProjection, classProjection: selectedClass, functionProjection: selected};
	}

	/** Revalidate the sealed syntax revision before macro/backend consumption. **/
	public function assertBodyRevisionCurrent():Void {
		TypedBodyInvariant.assertClasses(typedClasses);
		for (typedClass in typedClasses)
			for (typedFunction in typedClass.getFunctions())
				typedFunction.assertParsedBodyCurrent();
	}

	static function syntheticSourceOrigin(parsed:ParsedModule):CompilerModuleOrigin {
		final declaration = parsed.getDecl();
		final packagePath = StringTools.trim(HxModuleDecl.getPackagePath(declaration));
		final fileName = haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(parsed.getFilePath()));
		return CompilerModuleOrigin.synthetic(packagePath.length == 0 ? fileName : packagePath + "." + fileName);
	}
}
