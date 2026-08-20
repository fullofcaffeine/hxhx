import haxe.io.Path;

/**
	Target-neutral revisions observed for one fully typed Haxe module.

	The source revision identifies the module whose input changed directly. This
	keeps a caller whose typed output changed from pretending to be the cause of
	its own invalidation. The invalidator must reach that caller through an edge.
	The separate source-origin revision identifies the winning class-path slot and
	logical source module without embedding an absolute path. Equal bytes selected
	from a different source origin therefore recheck the provider without claiming
	that its public interface or implementation changed.
	The separate conditional-compilation observation identifies the evaluated `#if`
	inputs and selected branches. It can therefore recheck a module when a relevant
	define changes even if the filtered source happens to remain identical.
	The generated-declaration observation separately identifies fields and methods
	produced by build macros, whose result can change while the annotated source is
	byte-for-byte identical.
	The macro-file observation identifies external files explicitly registered for
	this module through `Context.registerModuleDependency`. It retains only path and
	content revisions, not the external path or bytes.

	The public-interface revision contains the resolved class and member signatures
	that another module can consume. The implementation revision additionally
	contains the complete parsed source and every typed statement and expression,
	including inline function bodies and field initializers. Explicit inline-call
	and constant-value edges decide which consumers receive an implementation
	change. An importer that never uses either implementation detail should not be
	invalidated merely because the declaration is public.

	These are exact in-memory identities, not a persistent cache format. A future
	typed-module cache must replace the large implementation identity with a measured
	native digest while retaining enough evidence to reject collisions.
**/
class CompilerTypedModuleRevision {
	public final modulePath:String;
	public final sourceRevision:String;
	public final sourceOriginRevision:String;
	public final sourceOriginDescription:String;
	public final conditionalCompilation:CompilerConditionalCompilationObservation;
	public final generatedDeclarations:CompilerGeneratedDeclarationObservation;
	public final macroFileDependencies:CompilerMacroFileDependencyObservation;
	public final publicInterfaceRevision:String;
	public final implementationRevision:String;

	final canonicalIdentity:String;

	public function new(modulePath:String, publicInterfaceRevision:String, implementationRevision:String, ?sourceRevision:String,
			?sourceOriginRevision:String, ?sourceOriginDescription:String, ?conditionalCompilation:CompilerConditionalCompilationObservation,
			?generatedDeclarations:CompilerGeneratedDeclarationObservation, ?macroFileDependencies:CompilerMacroFileDependencyObservation) {
		this.modulePath = normalize(modulePath);
		this.publicInterfaceRevision = publicInterfaceRevision == null ? "" : publicInterfaceRevision;
		this.implementationRevision = implementationRevision == null ? "" : implementationRevision;
		this.sourceRevision = sourceRevision == null ? this.implementationRevision : sourceRevision;
		this.sourceOriginRevision = sourceOriginRevision == null ? CompilerCacheIdentity.encode(["synthetic-module-origin-v1", this.modulePath]) : sourceOriginRevision;
		this.sourceOriginDescription = sourceOriginDescription == null ? this.modulePath + "@synthetic" : sourceOriginDescription;
		this.conditionalCompilation = conditionalCompilation == null ? CompilerConditionalCompilationObservation.empty() : conditionalCompilation;
		this.generatedDeclarations = generatedDeclarations == null ? CompilerGeneratedDeclarationObservation.empty() : generatedDeclarations;
		this.macroFileDependencies = macroFileDependencies == null ? CompilerMacroFileDependencyObservation.empty() : macroFileDependencies;
		if (this.modulePath.length == 0)
			throw "typed module revision requires a module path";
		canonicalIdentity = CompilerCacheIdentity.encode([
			"compiler-typed-module-revision-v1",
			this.modulePath,
			this.sourceRevision,
			this.sourceOriginRevision,
			this.sourceOriginDescription,
			this.conditionalCompilation.getCanonicalIdentity(),
			this.generatedDeclarations.getCanonicalIdentity(),
			this.macroFileDependencies.getCanonicalIdentity(),
			this.publicInterfaceRevision,
			this.implementationRevision,
		]);
	}

	/** Return the complete exact identity of this sealed module observation. **/
	public function getCanonicalIdentity():String
		return canonicalIdentity;

	public static function fromTypedModule(module:TypedModule, ?macroFileDependencies:CompilerMacroFileDependencyObservation):CompilerTypedModuleRevision {
		if (module == null)
			throw "cannot observe a null typed module";
		final parsed = module.getParsed();
		final modulePath = semanticModulePath(module);
		final sourceOrigin = module.getSourceOrigin();
		final sourceOriginRevision = sourceOrigin.getSourceIdentity();
		final sourceOriginDescription = sourceOrigin.describeSource();
		final conditionalCompilation = module.getConditionalCompilation();
		final generatedDeclarations = module.getGeneratedDeclarations();
		final sourceRevision = CompilerCacheIdentity.encode(["typed-module-source-v2", modulePath, sourceOriginRevision, parsed.getSource()]);
		final publicFacts = new Array<Null<String>>();
		publicFacts.push("typed-module-public-interface-v4");
		publicFacts.push(modulePath);
		final declaration = parsed.getDecl();
		publicFacts.push(HxModuleDecl.getPackagePath(declaration));
		final directives = HxModuleDecl.getDirectives(declaration);
		// Local import spelling is an implementation input, not exported API. Public
		// signatures below record the exact provider identities selected by typing.
		// This prevents `import model.Api as Service` -> `... as Client` from
		// needlessly retyping modules that consume an otherwise unchanged API.
		for (typedClass in module.getTypedClasses())
			addPublicClassFacts(publicFacts, typedClass);
		final publicRevision = CompilerCacheIdentity.encode(publicFacts);
		final implementationFacts = new Array<Null<String>>();
		implementationFacts.push("typed-module-implementation-v9");
		implementationFacts.push(modulePath);
		implementationFacts.push(publicRevision);
		addDirectives(implementationFacts, directives);
		addResolvedDirectives(implementationFacts, module.getEnv().getResolvedDirectives());
		implementationFacts.push(parsed.getSource());
		for (typedClass in module.getTypedClasses()) {
			implementationFacts.push("typed-class");
			implementationFacts.push(HxClassDecl.getName(typedClass.getSourceDeclaration()));
			for (fieldInitializer in typedClass.getFieldInitializers()) {
				implementationFacts.push("typed-field-initializer");
				implementationFacts.push(fieldInitializer.getField().getCanonicalKey());
				implementationFacts.push(CompilerTypedTreeRevision.expression(fieldInitializer.getField()
					.getCanonicalKey(), fieldInitializer.getExpression()));
			}
			for (typedFunction in typedClass.getFunctions()) {
				implementationFacts.push("typed-function-body-revision");
				implementationFacts.push(CompilerTypedTreeRevision.functionBody(typedFunction));
			}
		}
		final implementationRevision = CompilerCacheIdentity.encode(implementationFacts);
		return new CompilerTypedModuleRevision(modulePath, publicRevision, implementationRevision, sourceRevision, sourceOriginRevision,
			sourceOriginDescription, conditionalCompilation, generatedDeclarations, macroFileDependencies);
	}

	public static function semanticModulePath(module:TypedModule):String {
		for (typedClass in module.getTypedClasses()) {
			final semanticInfo = typedClass.getSemanticInfo();
			if (semanticInfo != null && normalize(semanticInfo.getModulePath()).length > 0)
				return normalize(semanticInfo.getModulePath());
		}
		final parsed = module.getParsed();
		final packagePath = normalize(HxModuleDecl.getPackagePath(parsed.getDecl()));
		final fileName = Path.withoutExtension(Path.withoutDirectory(parsed.getFilePath()));
		return packagePath.length == 0 ? fileName : packagePath + "." + fileName;
	}

	/**
		Combine every typed contribution to one Haxe source module.

		Haxe modules may declare several types. The loader can therefore present the
		same source module more than once while resolving secondary types such as
		`haxe.Function` from `haxe/Constraints.hx`. Each contribution is useful, but
		the dependency graph needs one module revision containing their sorted union.
	**/
	public static function mergeContributions(modulePath:String, contributions:Array<CompilerTypedModuleRevision>):CompilerTypedModuleRevision {
		final normalizedPath = normalize(modulePath);
		if (normalizedPath.length == 0 || contributions == null || contributions.length == 0)
			throw "typed module revision merge requires a module path and at least one contribution";
		final sourceValues = new Array<String>();
		final sourceOriginValues = new Array<String>();
		final sourceOriginDescriptions = new Array<String>();
		final conditionalCompilations = new Array<CompilerConditionalCompilationObservation>();
		final generatedDeclarations = new Array<CompilerGeneratedDeclarationObservation>();
		final macroFileDependencies = new Array<CompilerMacroFileDependencyObservation>();
		final publicValues = new Array<String>();
		final implementationValues = new Array<String>();
		for (contribution in contributions) {
			if (contribution == null || contribution.modulePath != normalizedPath)
				throw "typed module revision merge received a contribution for a different module";
			sourceValues.push(contribution.sourceRevision);
			sourceOriginValues.push(contribution.sourceOriginRevision);
			sourceOriginDescriptions.push(contribution.sourceOriginDescription);
			conditionalCompilations.push(contribution.conditionalCompilation);
			generatedDeclarations.push(contribution.generatedDeclarations);
			macroFileDependencies.push(contribution.macroFileDependencies);
			publicValues.push(contribution.publicInterfaceRevision);
			implementationValues.push(contribution.implementationRevision);
		}
		final uniqueSourceValues = uniqueSorted(sourceValues);
		if (uniqueSourceValues.length != 1)
			throw 'typed module revision merge received conflicting source revisions for ${normalizedPath}';
		final uniqueSourceOriginValues = uniqueSorted(sourceOriginValues);
		if (uniqueSourceOriginValues.length != 1)
			throw 'typed module revision merge received conflicting source origins for ${normalizedPath}';
		final uniqueSourceOriginDescriptions = uniqueSorted(sourceOriginDescriptions);
		if (uniqueSourceOriginDescriptions.length != 1)
			throw 'typed module revision merge received conflicting source-origin descriptions for ${normalizedPath}';
		final conditionalRevisionValues = uniqueSorted([for (conditional in conditionalCompilations) conditional.getCanonicalIdentity()]);
		if (conditionalRevisionValues.length != 1)
			throw 'typed module revision merge received conflicting conditional-compilation observations for ${normalizedPath}';
		final generatedRevisionValues = uniqueSorted([for (generated in generatedDeclarations) generated.getCanonicalIdentity()]);
		if (generatedRevisionValues.length != 1)
			throw 'typed module revision merge received conflicting generated-declaration observations for ${normalizedPath}';
		final macroFileRevisionValues = uniqueSorted([for (observation in macroFileDependencies) observation.getCanonicalIdentity()]);
		if (macroFileRevisionValues.length != 1)
			throw 'typed module revision merge received conflicting macro-file dependency observations for ${normalizedPath}';
		final sourceRevision = uniqueSourceValues[0];
		final publicRevision = CompilerCacheIdentity.encode(["typed-module-public-interface-set-v1", normalizedPath].concat(uniqueSorted(publicValues)));
		final implementationRevision = CompilerCacheIdentity.encode(["typed-module-implementation-set-v1", normalizedPath].concat(uniqueSorted(implementationValues)));
		return new CompilerTypedModuleRevision(normalizedPath, publicRevision, implementationRevision, sourceRevision, uniqueSourceOriginValues[0],
			uniqueSourceOriginDescriptions[0], conditionalCompilations[0], generatedDeclarations[0], macroFileDependencies[0]);
	}

	static function addPublicClassFacts(out:Array<Null<String>>, typedClass:TypedClass):Void {
		final sourceClass = typedClass.getSourceDeclaration();
		final semanticInfo = typedClass.getSemanticInfo();
		out.push("class");
		out.push(HxClassDecl.getName(sourceClass));
		out.push(HxClassDecl.getIsInterface(sourceClass) ? "interface" : "class");
		out.push(HxClassDecl.getVisibility(sourceClass) == HxVisibility.Public ? "public" : "private");
		addResolvedHeaderType(out, "extends", typedClass.getResolvedExtends());
		for (implemented in typedClass.getResolvedImplements())
			addResolvedHeaderType(out, "implements", implemented);
		addStrings(out, HxClassDecl.getMetadata(sourceClass));

		for (field in HxClassDecl.getFields(sourceClass)) {
			if (HxFieldDecl.getVisibility(field) != HxVisibility.Public)
				continue;
			out.push("public-field");
			out.push(HxFieldDecl.getName(field));
			out.push(HxFieldDecl.getIsStatic(field) ? "static" : "instance");
			final resolvedFieldType = semanticInfo == null ? null : semanticInfo.fieldType(HxFieldDecl.getName(field));
			out.push(resolvedFieldType == null ? "unresolved:" + HxFieldDecl.getTypeHint(field) : resolvedFieldType.getSemanticKey());
			out.push(HxFieldDecl.getIsFinal(field) ? "final" : "mutable");
			out.push(HxFieldDecl.getPropertyGet(field));
			out.push(HxFieldDecl.getPropertySet(field));
			addStrings(out, HxFieldDecl.getMetadata(field));
			// Initializer values belong to the implementation revision. A caller that
			// may embed a final/inline value carries an explicit constant-value edge.
			// Keeping the value out of this module-wide public identity prevents an
			// import-only module from looking like it consumed every public constant.
			// When the field has no trustworthy written/resolved type, retain the
			// initializer as a conservative fallback because changing it may change the
			// public type that callers see.
			final writtenType = StringTools.trim(HxFieldDecl.getTypeHint(field));
			if (writtenType.length == 0 || resolvedFieldType == null || resolvedFieldType.isUnknown()) {
				out.push("public-field-inferred-type-fallback");
				out.push(HxFieldDecl.getInitText(field));
			}
		}

		for (typedFunction in typedClass.getFunctions()) {
			final sourceFunction = typedFunction.getSourceDeclaration();
			if (HxFunctionDecl.getVisibility(sourceFunction) != HxVisibility.Public)
				continue;
			out.push("public-function");
			out.push(typedFunction.getStableIdentity());
			out.push(HxFunctionDecl.getIsStatic(sourceFunction) ? "static" : "instance");
			addStrings(out, HxFunctionDecl.getMetadata(sourceFunction));
			final declaration = typedFunction.getDeclaration();
			if (declaration != null) {
				final signature = declaration.getSignature();
				addTypes(out, signature.getArgs());
				addBools(out, signature.getArgOptional());
				addBools(out, signature.getArgRest());
				out.push(signature.getReturnType().getSemanticKey());
				out.push(declaration.getIsInline() ? "inline" : "ordinary");
			} else {
				out.push(HxFunctionDecl.getReturnTypeHint(sourceFunction));
				for (argument in HxFunctionDecl.getArgs(sourceFunction)) {
					out.push(HxFunctionArg.getName(argument));
					out.push(HxFunctionArg.getTypeHint(argument));
					out.push(HxFunctionArg.getIsOptional(argument) ? "optional" : "required");
					out.push(HxFunctionArg.getIsRest(argument) ? "rest" : "ordinary");
					addStrings(out, HxFunctionArg.getMetadata(argument));
				}
			}
		}
	}

	static function addResolvedHeaderType(out:Array<Null<String>>, label:String, type:Null<TyType>):Void {
		out.push(label);
		out.push(type == null ? "none" : type.getSemanticKey());
	}

	static function addTypes(out:Array<Null<String>>, values:Array<TyType>):Void {
		out.push(values == null ? "-1" : Std.string(values.length));
		if (values != null)
			for (value in values)
				out.push(value == null ? "unknown" : value.getSemanticKey());
	}

	static function addDirectives(out:Array<Null<String>>, directives:Array<HxModuleDirective>):Void {
		out.push(directives == null ? "-1" : Std.string(directives.length));
		if (directives != null)
			for (directive in directives)
				out.push(HxModuleDirective.canonicalIdentity(directive));
	}

	/** Include the exact providers chosen by typing in the reusable module identity. **/
	static function addResolvedDirectives(out:Array<Null<String>>, directives:Array<TyModuleDirective>):Void {
		out.push(directives == null ? "-1" : Std.string(directives.length));
		if (directives != null)
			for (directive in directives)
				out.push(directive.canonicalIdentity());
	}

	static function addBools(out:Array<Null<String>>, values:Array<Bool>):Void {
		out.push(values == null ? "-1" : Std.string(values.length));
		if (values != null)
			for (value in values)
				out.push(value ? "true" : "false");
	}

	static function addStrings(out:Array<Null<String>>, values:Array<String>):Void {
		out.push(values == null ? "-1" : Std.string(values.length));
		if (values != null)
			for (value in values)
				out.push(value);
	}

	static function uniqueSorted(values:Array<String>):Array<String> {
		final seen = new haxe.ds.StringMap<Bool>();
		for (value in values)
			seen.set(value == null ? "" : value, true);
		final out = [for (value in seen.keys()) value];
		out.sort(compareText);
		return out;
	}

	static function compareText(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);

	static function normalize(value:String):String
		return value == null ? "" : StringTools.trim(value);
}
