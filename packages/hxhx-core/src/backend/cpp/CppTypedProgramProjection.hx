package backend.cpp;

/** One strict module and its source location within a C++ compilation request. */
typedef CppTypedModuleProjection = {
	final projection:TypedBackendModuleProjection;
	final sourcePath:String;
	final moduleIdentity:String;
};

/** Target representation inputs for a field already selected by shared typing. */
typedef CppSelectedFieldDeclaration = {
	final owner:HxClassDecl;
	final declaration:HxFieldDecl;
};

/** Exact function and class that own a projected signature parameter. */
typedef CppArgumentOwner = {
	final owner:HxClassDecl;
	final declaration:HxFunctionDecl;
};

/**
	Binds C++ traversal to the exact declarations rebuilt from sealed typed bodies.

	The legacy declaration tree is a different object graph. It cannot supply
	function or initializer catalogs for these declarations, even when names and
	source positions match. This request-owned index retains each strict owner
	without cloning bodies or changing shared compiler facts.
**/
class CppTypedProgramProjection {
	final source:backend.GenIrProgram;
	final modules:Array<CppTypedModuleProjection> = [];
	final importedClasses = new haxe.ds.ObjectMap<TypedBackendModuleProjection, Array<TyNominalTypeId>>();
	final classes = new haxe.ds.ObjectMap<HxClassDecl, TypedBackendClassProjection>();
	final functions = new haxe.ds.ObjectMap<HxFunctionDecl, TypedBackendFunctionProjection>();
	final functionOwners = new haxe.ds.ObjectMap<HxFunctionDecl, HxClassDecl>();
	final argumentOwners = new haxe.ds.ObjectMap<HxFunctionArg, CppArgumentOwner>();
	final initializers = new haxe.ds.ObjectMap<HxFieldDecl, TypedBackendFieldInitializerProjection>();
	final initializerOwners = new haxe.ds.ObjectMap<HxFieldDecl, HxClassDecl>();
	final programRevision:String;
	var classesByIdentity:Null<haxe.ds.StringMap<HxClassDecl>>;

	public function new(program:backend.GenIrProgram) {
		if (program == null)
			throw "C++ typed program requires a program";
		program.assertTypedBodyRevisionsCurrent();
		source = program;
		programRevision = program.getTypedProgramRevision().getCanonicalIdentity();
		final executableIdentities = new haxe.ds.StringMap<Bool>();
		for (typed in program.getTypedModules()) {
			CppNamedCallAdmission.module(typed);
			final projection = typed.getBackendProjection();
			importedClasses.set(projection, [
				for (directive in typed.getEnv().getResolvedDirectives())
					for (provider in directive.getProviders())
						provider
			]);
			modules.push({
				projection: projection,
				sourcePath: typed.getParsed().getFilePath(),
				moduleIdentity: typed.getSourceOrigin().sourceModulePath
			});
			for (cls in projection.getClasses()) {
				final declaration = cls.getDeclaration();
				if (classes.exists(declaration))
					throw "C++ typed program contains a duplicate class projection";
				classes.set(declaration, cls);
				for (fn in cls.getFunctions()) {
					final identity = fn.getStableIdentity();
					if (functions.exists(fn.getDeclaration()) || executableIdentities.exists(identity))
						throw "C++ typed program contains duplicate executable " + identity;
					executableIdentities.set(identity, true);
					functions.set(fn.getDeclaration(), fn);
					functionOwners.set(fn.getDeclaration(), declaration);
					for (argument in HxFunctionDecl.getArgs(fn.getDeclaration())) {
						if (argumentOwners.exists(argument))
							throw "C++ typed program contains a parameter shared by two declarations";
						argumentOwners.set(argument, {owner: declaration, declaration: fn.getDeclaration()});
					}
				}
				for (initializer in cls.getFieldInitializers()) {
					final identity = initializer.getStableIdentity();
					if (initializers.exists(initializer.getDeclaration()) || executableIdentities.exists(identity))
						throw "C++ typed program contains duplicate executable " + identity;
					executableIdentities.set(identity, true);
					initializers.set(initializer.getDeclaration(), initializer);
					initializerOwners.set(initializer.getDeclaration(), declaration);
				}
			}
		}
	}

	public function getModules():Array<CppTypedModuleProjection>
		return modules.copy();

	/** Module ordering consumes resolved imports from this program, never reparsed import spellings. */
	public function getImportedClasses(module:TypedBackendModuleProjection):Array<TyNominalTypeId> {
		final selected = importedClasses.get(module);
		if (selected == null)
			throw "C++ imports belong to another program projection";
		return selected.copy();
	}

	public function getProgramRevision():String
		return programRevision;

	/** A caller's same-named local cannot stand in for this parameter's declaration. */
	public function requireArgumentOwner(argument:HxFunctionArg):CppArgumentOwner {
		final selected = argument == null ? null : argumentOwners.get(argument);
		if (selected == null)
			throw "C++ typed program cannot identify a foreign function parameter";
		return selected;
	}

	/** Recheck source revisions before publishing output from this request. */
	public function assertCurrent():Void
		source.assertTypedBodyRevisionsCurrent();

	/** Reject unsupported operations in all modules, including unreachable bodies. */
	public function assertRuntimeTypeOperandsAbsent():Void {
		for (module in modules)
			module.projection.assertRuntimeTypeOperandsAbsent("C++ backend");
	}

	public function requireClass(declaration:HxClassDecl):TypedBackendClassProjection {
		final selected = declaration == null ? null : classes.get(declaration);
		if (selected == null)
			throw "C++ typed program cannot identify a foreign class declaration";
		return selected;
	}

	/** Resolve a selected semantic owner without choosing a same-named class from another module. */
	public function requireClassIdentity(identity:String):HxClassDecl {
		if (classesByIdentity == null) {
			final indexed = new haxe.ds.StringMap<HxClassDecl>();
			for (module in modules)
				for (cls in module.projection.getClasses()) {
					final canonical = cls.requireSemanticFacts().getClassIdentity();
					if (indexed.exists(canonical))
						throw "C++ typed program contains duplicate class identity " + canonical;
					indexed.set(canonical, cls.getDeclaration());
				}
			classesByIdentity = indexed;
		}
		final selected = classesByIdentity.get(identity);
		if (selected == null)
			throw "C++ typed program has no selected class owner " + identity;
		return selected;
	}

	/** Retain the exact owner when an existing target field representation needs its declaration. */
	public function requireFieldDeclaration(field:TyFieldInfo):CppSelectedFieldDeclaration {
		final owner = requireClassIdentity(field.getOwner().getCanonicalName());
		if (requireClass(owner).requireSemanticFacts().getModuleIdentity() != field.getModulePath())
			throw "C++ selected field belongs to another source module";
		for (declaration in HxClassDecl.getFields(owner))
			if (HxFieldDecl.getName(declaration) == field.getName() && HxFieldDecl.getIsStatic(declaration) == field.getIsStatic())
				return {owner: owner, declaration: declaration};
		throw "C++ selected class has no field " + field.getCanonicalKey();
	}

	/** Same-named declarations cannot borrow another class's function facts. */
	public function requireFunction(owner:HxClassDecl, declaration:HxFunctionDecl):TypedBackendFunctionProjection {
		requireClass(owner);
		final selected = declaration == null ? null : functions.get(declaration);
		if (selected == null || functionOwners.get(declaration) != owner)
			throw "C++ typed program cannot identify a function in the selected class";
		return selected;
	}

	/** Select a declaration's class when an analysis starts from a caller scope. */
	public function requireFunctionOwner(declaration:HxFunctionDecl):HxClassDecl {
		final selected = declaration == null ? null : functionOwners.get(declaration);
		if (selected == null)
			throw "C++ typed program cannot identify a foreign function owner";
		return selected;
	}

	/** Initializers keep their own executable identity when emitted in constructors. */
	public function requireInitializer(owner:HxClassDecl, declaration:HxFieldDecl):TypedBackendFieldInitializerProjection {
		requireClass(owner);
		final selected = declaration == null ? null : initializers.get(declaration);
		if (selected == null || initializerOwners.get(declaration) != owner)
			throw "C++ typed program cannot identify an initializer in the selected class: "
				+ HxClassDecl.getName(owner)
				+ "."
				+ (declaration == null ? "<missing>" : HxFieldDecl.getName(declaration));
		return selected;
	}

	/** Plan authored symbols only after the exact function and class are selected. */
	public function functionLocals(owner:HxClassDecl, declaration:HxFunctionDecl, ?fixedSymbols:Array<String>):CppExecutableLocals {
		return new CppExecutableLocals(FunctionBody(requireFunction(owner, declaration)), fixedSymbols);
	}

	/** An initializer keeps its own catalogs even when emitted inside a constructor. */
	public function initializerLocals(owner:HxClassDecl, declaration:HxFieldDecl, ?fixedSymbols:Array<String>):CppExecutableLocals {
		return new CppExecutableLocals(FieldInitializer(requireInitializer(owner, declaration)), fixedSymbols);
	}

	/** Resolve inheritance through canonical typed identities when an operation needs it. */
	public function getClassGraph():TypedBackendClassGraph {
		return new TypedBackendClassGraph(programRevision, [
			for (module in modules)
				for (cls in module.projection.getClasses())
					cls.requireSemanticFacts()
		]);
	}
}
