/** Exact declarations selected before reference traversal; this record does not remove emitted code. */
typedef TypedFeatureRootSet = {
	final program:MacroExpandedProgram;
	final classes:Array<TypedClass>;
	final functions:Array<TypedFunction>;
	final fields:Array<TyFieldInfo>;
}

/**
	Select entry-point, ordinary project-code and explicit keep roots for feature discovery.
	The source catalog distinguishes SDK providers from project overrides. Upstream
	retains project feature definitions under std/no but requires SDK references in
	both modes. Class initialization is added by reference traversal when its class
	becomes retained. Keep-sub ancestry and exported declarations retain members;
	keep-init retains class initialization separately. This does not remove emitted
	declarations. Emission retention and dynamic method binding remain separate work.
**/
function select(input:{
	program:MacroExpandedProgram,
	sources:TypedFeatureSourceCatalog,
	entryPoint:TypedFunction,
	mode:String
}):TypedFeatureRootSet {
	final retainProject = switch (input.mode) {
		case "full": false;
		case "std" | "no": true;
		case _: throw "unsupported feature retention mode: " + input.mode;
	};
	input.program.assertTypedBodyRevisionsCurrent();
	final providers = new haxe.ds.StringMap<TypedClass>();
	for (module in input.program.getTypedModules())
		for (owner in module.getTypedClasses()) {
			final info = owner.getSemanticInfo();
			if (info == null || providers.exists(info.getIdentity().getCanonicalName()))
				throw "feature roots require unique semantic class providers";
			providers.set(info.getIdentity().getCanonicalName(), owner);
		}
	final classes = new Array<TypedClass>();
	final functions = new Array<TypedFunction>();
	final fields = new Array<TyFieldInfo>();
	var entryFound = false;
	for (module in input.program.getTypedModules()) {
		final project = !input.sources.isStandardLibrary(input.program, module);
		for (owner in module.getTypedClasses()) {
			final metadata = HxClassDecl.getMetadata(owner.getSourceDeclaration());
			final retainAll = (retainProject && project) || has(metadata, "keep") || has(metadata, "expose") || inheritsKeepSub(owner, providers);
			if (retainAll || has(metadata, "keepInit"))
				classes.push(owner);
			for (fn in owner.getFunctions()) {
				if (fn == input.entryPoint)
					entryFound = true;
				final declaration = fn.getDeclaration();
				if (declaration == null)
					throw "feature roots require exact function declarations";
				if (fn == input.entryPoint
					|| retainAll
					|| has(declaration.getMetadata(), "keep")
					|| has(declaration.getMetadata(), "expose"))
					functions.push(fn);
			}
			final info = owner.getSemanticInfo();
			if (info == null)
				throw "feature roots require exact class declarations";
			for (source in HxClassDecl.getFields(owner.getSourceDeclaration())) {
				if (!retainAll && !has(HxFieldDecl.getMetadata(source), "keep") && !has(HxFieldDecl.getMetadata(source), "expose"))
					continue;
				final field = info.fieldInfo(HxFieldDecl.getName(source));
				if (field == null)
					throw "feature roots require exact field declarations";
				fields.push(field);
			}
		}
	}
	if (!entryFound)
		throw "feature roots require an owned entry function";
	return {
		program: input.program,
		classes: classes,
		functions: functions,
		fields: fields
	};
}

/** Match a parsed metadata name; arguments can select an export name without changing its retention rule. */
private function has(metadata:Array<String>, expected:String):Bool {
	for (entry in metadata) {
		var name = StringTools.trim(entry);
		while (StringTools.startsWith(name, "@") || StringTools.startsWith(name, ":"))
			name = name.substr(1);
		if (name == expected || StringTools.startsWith(name, expected + "("))
			return true;
	}
	return false;
}

/** A keepSub ancestor retains loaded descendants through exact resolved inheritance. */
private function inheritsKeepSub(owner:TypedClass, providers:haxe.ds.StringMap<TypedClass>):Bool {
	final visited = new haxe.ds.ObjectMap<TypedClass, Bool>();
	function visit(current:TypedClass):Bool {
		if (visited.exists(current))
			return false;
		visited.set(current, true);
		if (has(HxClassDecl.getMetadata(current.getSourceDeclaration()), "keepSub"))
			return true;
		final parents = current.getResolvedImplements().concat(current.getResolvedInterfaceExtends());
		if (current.getResolvedExtends() != null)
			parents.push(current.getResolvedExtends());
		for (parent in parents) {
			final identity = parent.getNominalIdentity();
			if (identity == null)
				throw "feature inheritance requires an exact nominal provider";
			final provider = providers.get(identity.getCanonicalName());
			if (provider == null)
				throw "feature class reference has no exact program provider: " + identity.getCanonicalName();
			if (visit(provider))
				return true;
		}
		return false;
	}
	return visit(owner);
}
