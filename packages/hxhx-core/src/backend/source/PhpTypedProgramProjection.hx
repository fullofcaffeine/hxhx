package backend.source;

import backend.source.PhpModuleRenderFacts.PhpModuleRenderContribution;

typedef PhpTypedModuleProjection = {
	final typed:TypedModule;
	final projection:TypedBackendModuleProjection;
	final moduleIdentity:String;
};

private typedef PhpTypedFunctionOwner = {
	final projectedClass:TypedBackendClassProjection;
	final moduleIdentity:String;
};

/**
	Own the immutable typed module and function records consumed by one PHP generation.

	The PHP emitter still walks a temporary source-shaped declaration tree, but
	every ordinary function object in that tree is paired here with the exact
	`TypedBackendFunctionProjection` created from the sealed typed body. This
	lets PHP-specific adapters reuse a function from another projected class
	without falling back to a parsed body or correlating declarations by name.
	Program, module, class, function, initializer, and inheritance facts are
	joined through this owner before a request-owned function renderer starts.

	Object identity is used only inside this one immutable program snapshot.
	Cross-request and cache identity continues to come from each projection's
	stable function identity.
**/
class PhpTypedProgramProjection {
	final modules:Array<PhpTypedModuleProjection>;
	final functions:haxe.ds.ObjectMap<HxFunctionDecl, TypedBackendFunctionProjection>;
	final functionOwners:haxe.ds.ObjectMap<HxFunctionDecl, PhpTypedFunctionOwner>;
	final fieldInitializers:haxe.ds.ObjectMap<HxFieldDecl, TypedBackendFieldInitializerProjection>;
	final fieldInitializerOwners:haxe.ds.ObjectMap<HxFieldDecl, PhpTypedFunctionOwner>;
	final functionsByStableIdentity:haxe.ds.StringMap<TypedBackendFunctionProjection>;
	final ownersByStableIdentity:haxe.ds.StringMap<PhpTypedFunctionOwner>;
	final classOwners:haxe.ds.ObjectMap<HxClassDecl, String>;
	final classModuleOwners:haxe.ds.ObjectMap<HxClassDecl, String>;
	final stableFunctions:haxe.ds.StringMap<String>;
	final typedProgramRevision:CompilerTypedProgramRevision;

	public function new(program:GenIrProgram) {
		if (program == null)
			throw "PHP typed program projection requires a program";
		modules = [];
		functions = new haxe.ds.ObjectMap<HxFunctionDecl, TypedBackendFunctionProjection>();
		functionOwners = new haxe.ds.ObjectMap<HxFunctionDecl, PhpTypedFunctionOwner>();
		fieldInitializers = new haxe.ds.ObjectMap<HxFieldDecl, TypedBackendFieldInitializerProjection>();
		fieldInitializerOwners = new haxe.ds.ObjectMap<HxFieldDecl, PhpTypedFunctionOwner>();
		functionsByStableIdentity = new haxe.ds.StringMap<TypedBackendFunctionProjection>();
		ownersByStableIdentity = new haxe.ds.StringMap<PhpTypedFunctionOwner>();
		classOwners = new haxe.ds.ObjectMap<HxClassDecl, String>();
		classModuleOwners = new haxe.ds.ObjectMap<HxClassDecl, String>();
		stableFunctions = new haxe.ds.StringMap<String>();
		typedProgramRevision = program.getTypedProgramRevision();
		for (typed in program.getTypedModules()) {
			final projection = typed.getBackendProjection();
			final moduleIdentity = typed.getSourceOrigin().sourceModulePath;
			modules.push({typed: typed, projection: projection, moduleIdentity: moduleIdentity});
			for (projectedClass in projection.getClasses()) {
				final projectedClassDeclaration = projectedClass.getDeclaration();
				final classIdentity = moduleIdentity + "." + HxClassDecl.getName(projectedClassDeclaration);
				if (!classOwners.exists(projectedClassDeclaration))
					classOwners.set(projectedClassDeclaration, classIdentity);
				if (!classModuleOwners.exists(projectedClassDeclaration))
					classModuleOwners.set(projectedClassDeclaration, moduleIdentity);
				for (projectedFunction in projectedClass.getFunctions()) {
					final declaration = projectedFunction.getDeclaration();
					final stableIdentity = projectedFunction.getStableIdentity();
					final stableProgramIdentity = moduleIdentity + "|" + stableIdentity;
					if (functions.exists(declaration) || stableFunctions.exists(stableProgramIdentity))
						throw "PHP typed program projection contains a duplicate function projection "
							+ classIdentity
							+ "."
							+ HxFunctionDecl.getName(declaration)
							+ " ("
							+ stableIdentity
							+ ")";
					functions.set(declaration, projectedFunction);
					functionOwners.set(declaration, {
						projectedClass: projectedClass,
						moduleIdentity: moduleIdentity
					});
					final previousStableProjection = functionsByStableIdentity.get(stableIdentity);
					if (previousStableProjection != null)
						throw "PHP typed program projection contains duplicate stable function identity " + stableIdentity;
					functionsByStableIdentity.set(stableIdentity, projectedFunction);
					ownersByStableIdentity.set(stableIdentity, {
						projectedClass: projectedClass,
						moduleIdentity: moduleIdentity
					});
					stableFunctions.set(stableProgramIdentity, classIdentity + "." + HxFunctionDecl.getName(declaration));
				}
				for (initializer in projectedClass.getFieldInitializers()) {
					final declaration = initializer.getDeclaration();
					if (fieldInitializers.exists(declaration))
						throw "PHP typed program projection contains duplicate field initializer " + initializer.getStableIdentity();
					fieldInitializers.set(declaration, initializer);
					fieldInitializerOwners.set(declaration, {
						projectedClass: projectedClass,
						moduleIdentity: moduleIdentity
					});
				}
			}
		}
	}

	public function getModules():Array<PhpTypedModuleProjection>
		return modules.copy();

	/**
		Return the exact source-module identity that owns a projected class.

		Support rendering uses this identity to select the same immutable module
		naming facts as executable function rendering. A missing class is an
		integrity failure; callers must not reconstruct ownership from a short
		class name or parsed source path.
	**/
	public function requireClassModuleIdentity(declaration:HxClassDecl):String {
		if (declaration == null)
			throw "PHP typed program projection received a null class ownership request";
		final moduleIdentity = classModuleOwners.get(declaration);
		if (moduleIdentity == null)
			throw "PHP typed program projection cannot find module ownership for " + HxClassDecl.getName(declaration);
		return moduleIdentity;
	}

	/** Return the exact target-neutral program revision supplied by the typed owner. **/
	public function getProgramRevision():String
		return typedProgramRevision.getCanonicalIdentity();

	/**
		Build the exact target-neutral class graph used by PHP function plans.

		Construction remains lazy, but production plan creation now consumes this
		graph. An absent or conflicting superclass fails before body rendering
		instead of falling back to the old short-name `classesByName` search.
	**/
	public function getClassGraph():TypedBackendClassGraph {
		final facts = new Array<TypedBackendClassSemanticFacts>();
		for (module in modules)
			for (projectedClass in module.projection.getClasses())
				facts.push(projectedClass.requireSemanticFacts());
		return new TypedBackendClassGraph(getProgramRevision(), facts);
	}

	/**
		Build the immutable PHP naming facts for this exact program.

		Construction is lazy and request-owned function renderers consume the
		result. Program and support-scaffolding consumers move in Slice 4, when
		the remaining equivalent static tables are removed.
	**/
	public function getProgramRenderFacts():PhpProgramRenderFacts
		return new PhpProgramRenderFacts(getProgramRevision(), [
			for (module in modules)
				{
					moduleIdentity: module.moduleIdentity,
					projection: module.projection
				}
		]);

	/**
		Build the immutable naming view for one exact Haxe source module.

		Construction remains lazy. Repeated typed contributions for secondary types
		are merged under the same source module, while the sealed program revision
		supplies the one matching module revision. A missing or duplicate revision
		is an integrity failure before rendering.
	**/
	public function getModuleRenderFacts(moduleIdentity:String):PhpModuleRenderFacts {
		final normalizedIdentity = moduleIdentity == null ? "" : StringTools.trim(moduleIdentity);
		if (normalizedIdentity.length == 0)
			throw "PHP module render facts require an exact source-module identity";
		final contributions = new Array<PhpModuleRenderContribution>();
		for (module in modules)
			if (module.moduleIdentity == normalizedIdentity)
				contributions.push({
					projection: module.projection,
					resolvedDirectives: module.typed.getEnv().getResolvedDirectives()
				});
		if (contributions.length == 0)
			throw "PHP typed program projection does not contain source module " + normalizedIdentity;
		var selectedRevision:Null<CompilerTypedModuleRevision> = null;
		for (revision in typedProgramRevision.getModules())
			if (revision.modulePath == normalizedIdentity) {
				if (selectedRevision != null)
					throw "PHP typed program projection contains duplicate module revision " + normalizedIdentity;
				selectedRevision = revision;
			}
		if (selectedRevision == null)
			throw "PHP typed program projection cannot find module revision " + normalizedIdentity;
		return new PhpModuleRenderFacts(getProgramRenderFacts(), selectedRevision.getCanonicalIdentity(), normalizedIdentity, contributions);
	}

	/**
		Return the exact typed record paired with a projected function object.

		A miss means an ordinary Haxe declaration escaped the typed program
		snapshot. PHP must stop rather than recover the body from source text.
	**/
	public function requireFunction(declaration:HxFunctionDecl, ownerClass:HxClassDecl):TypedBackendFunctionProjection {
		final owner = ownerClass == null ? "<unknown-module>.<unknown-class>" : classOwners.get(ownerClass);
		final ownerIdentity = owner == null ? "<unknown-module>." + HxClassDecl.getName(ownerClass) : owner;
		if (declaration == null)
			throw "PHP typed program projection received a null function for " + ownerIdentity;
		final projection = functions.get(declaration);
		if (projection == null)
			throw "PHP typed program projection is missing " + ownerIdentity + "." + HxFunctionDecl.getName(declaration);
		return projection;
	}

	/**
		Build the sealed production plan for one exact projected function.

		The declaration object is only the lookup token inside this immutable
		program snapshot. Plan construction itself consumes exact typed class,
		module, graph, local, field, function, and body facts.
	**/
	public function requireFunctionLoweringPlan(declaration:HxFunctionDecl, ?renderClassUsesThisValueSlot:Bool):PhpFunctionLoweringPlan {
		if (declaration == null)
			throw "PHP typed program projection received a null function plan request";
		final projection = functions.get(declaration);
		final owner = functionOwners.get(declaration);
		if (projection == null || owner == null)
			throw "PHP typed program projection cannot plan unknown function " + HxFunctionDecl.getName(declaration);
		final classFacts = owner.projectedClass.requireSemanticFacts();
		if (classFacts.getModuleIdentity() != owner.moduleIdentity)
			throw "PHP typed program projection contains conflicting module ownership for " + projection.getStableIdentity();
		final usesThisValueSlot = renderClassUsesThisValueSlot == null ? PhpThisValueSlotFacts.classNeedsValueSlot(owner.projectedClass.getFunctions()) : renderClassUsesThisValueSlot;
		return new PhpFunctionLoweringPlan(getProgramRenderFacts(), getModuleRenderFacts(owner.moduleIdentity), getClassGraph(), classFacts,
			usesThisValueSlot, projection);
	}

	/** Build the request-owned PHP renderer for one exact projected function. **/
	public function requireFunctionBodyRenderer(programRenderer:PhpProgramBodyRenderer, declaration:HxFunctionDecl,
			?renderClassUsesThisValueSlot:Bool):PhpFunctionBodyRenderer {
		if (programRenderer == null)
			throw "PHP typed program projection requires a request-owned program renderer";
		if (declaration == null)
			throw "PHP typed program projection received a null function renderer request";
		final owner = functionOwners.get(declaration);
		if (owner == null)
			throw "PHP typed program projection cannot render unknown function " + HxFunctionDecl.getName(declaration);
		final programFacts = getProgramRenderFacts();
		final moduleFacts = getModuleRenderFacts(owner.moduleIdentity);
		final plan = requireFunctionLoweringPlan(declaration, renderClassUsesThisValueSlot);
		return new PhpFunctionBodyRenderer(programRenderer, programFacts, moduleFacts, plan);
	}

	/**
		Build a request-owned renderer for one exact typed field initializer.

		Field initializers use the same recursive PHP syntax kernel as functions,
		but their locals and field reads come from their own typed executable
		projection. They never borrow a method's lexical plan.
	**/
	public function requireFieldInitializerRenderer(programRenderer:PhpProgramBodyRenderer, declaration:HxFieldDecl):PhpFunctionBodyRenderer {
		if (programRenderer == null)
			throw "PHP typed program projection requires a request-owned program renderer";
		if (declaration == null)
			throw "PHP typed program projection received a null field initializer renderer request";
		final projection = fieldInitializers.get(declaration);
		final owner = fieldInitializerOwners.get(declaration);
		if (projection == null || owner == null)
			throw "PHP typed program projection cannot render unknown field initializer " + HxFieldDecl.getName(declaration);
		final classFacts = owner.projectedClass.requireSemanticFacts();
		final programFacts = getProgramRenderFacts();
		final moduleFacts = getModuleRenderFacts(owner.moduleIdentity);
		final plan = new PhpFunctionLoweringPlan(programFacts, moduleFacts, getClassGraph(), classFacts, false, null, projection);
		return new PhpFunctionBodyRenderer(programRenderer, programFacts, moduleFacts, plan);
	}

	/**
		Build a renderer from an exact strict function projection.

		The selected main projection can be a separately materialized source view,
		so object identity is not a valid join key. Its stable typed declaration
		identity is.
	**/
	public function requireProjectedFunctionBodyRenderer(programRenderer:PhpProgramBodyRenderer,
			projection:TypedBackendFunctionProjection):PhpFunctionBodyRenderer {
		if (programRenderer == null)
			throw "PHP typed program projection requires a request-owned program renderer";
		if (projection == null)
			throw "PHP typed program projection received a null strict function renderer request";
		final identity = projection.getStableIdentity();
		final canonicalProjection = functionsByStableIdentity.get(identity);
		final owner = ownersByStableIdentity.get(identity);
		if (canonicalProjection == null || owner == null)
			throw "PHP typed program projection cannot render unknown strict function " + identity;
		if (canonicalProjection.getBodyRevision() != projection.getBodyRevision())
			throw "PHP typed program projection received conflicting body revisions for " + identity;
		final programFacts = getProgramRenderFacts();
		final moduleFacts = getModuleRenderFacts(owner.moduleIdentity);
		final plan = new PhpFunctionLoweringPlan(programFacts, moduleFacts, getClassGraph(), owner.projectedClass.requireSemanticFacts(),
			PhpThisValueSlotFacts.classNeedsValueSlot(owner.projectedClass.getFunctions()), projection);
		return new PhpFunctionBodyRenderer(programRenderer, programFacts, moduleFacts, plan);
	}
}
