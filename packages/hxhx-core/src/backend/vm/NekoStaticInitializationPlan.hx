package backend.vm;

/** Literal native-library binding installed before startup, without removing its ordinary assignment. */
typedef NekoEarlyNativeBinding = {
	final library:String;
	final primitive:String;
	final arity:Int;
}

/** Bind shared startup order to the exact program before selecting Neko initializer roots. */
class NekoStaticInitializationPlan {
	final order:TypedStaticStartupOrder;
	final program:NekoTypedProgramProjection;

	public function new(source:backend.GenIrProgram, program:NekoTypedProgramProjection) {
		this.program = program;
		final modules = new Array<TypedStaticStartupOrder.TypedStartupModule>();
		for (typed in source.getTypedModules()) {
			final imports = new Array<TyNominalTypeId>();
			for (directive in typed.getEnv().getResolvedDirectives())
				for (provider in directive.getProviders())
					imports.push(provider);
			modules.push({moduleIdentity: typed.getSourceOrigin().sourceModulePath, projection: typed.getBackendProjection(), importedClasses: imports});
		}
		order = new TypedStaticStartupOrder({modules: modules, assertCurrent: source.assertTypedBodyRevisionsCurrent});
	}

	/** Extern declarations have no authored startup; all loaded ordinary classes retain their effects. */
	public function getClasses():Array<TypedBackendClassProjection> {
		final result = new Array<TypedBackendClassProjection>();
		for (owner in order.getClasses()) {
			final facts = owner.requireSemanticFacts();
			if (program.requireClass(facts.getClassIdentity()) != owner)
				throw "Neko startup order belongs to another program projection";
			if (!facts.getIsExtern())
				result.push(owner);
		}
		return result;
	}

	/** A direct function value is installed once before startup effects; factory calls stay ordered. */
	public function isEarlyFunction(initializer:TypedBackendFieldInitializerProjection):Bool {
		initializer.assertCurrent();
		if (program.requireDeclaredInitializer(initializer.getDeclaration()) != initializer)
			throw "Neko early initializer belongs to another program projection";
		if (!initializer.getField().getIsStatic())
			return false;
		final body = TypedControlStatements.initializerBody(initializer.getExpression(), initializer.getStableIdentity());
		if (body.statements.length != 0 || body.value == null)
			return false;
		var value = body.value;
		switch value {
			case ECast(_, _):
				if (initializer.findCast(value) != null)
					return false;
				value = initializer.requireCaptureCatalog().requireAscribedClosure(value);
			case _:
		}
		return initializer.findLambda(value) != null;
	}

	/** Only the exact native loader with literal arguments and Dynamic storage has an early binding. */
	public function earlyNativeBinding(initializer:TypedBackendFieldInitializerProjection):Null<NekoEarlyNativeBinding> {
		initializer.assertCurrent();
		if (program.requireDeclaredInitializer(initializer.getDeclaration()) != initializer)
			throw "Neko native initializer belongs to another program projection";
		if (!initializer.getField().getIsStatic())
			return null;
		final field = initializer.getField();
		final owner = program.requireClass(field.getOwner().getCanonicalName());
		final fieldType = owner.requireSemanticFacts().requireField(field).semanticType;
		if (!fieldType.isDynamic())
			return null;
		final body = TypedControlStatements.initializerBody(initializer.getExpression(), initializer.getStableIdentity());
		if (body.statements.length != 0 || body.value == null)
			return null;
		final selected = NekoExactStaticCallPlan.fromExpression(program, body.value);
		if (selected == null)
			return null;
		final declaration = selected.selected.body.requireSemanticDeclaration();
		if (declaration.getOwner().getCanonicalName() != "neko.Lib" || declaration.getSignature().getName() != "load")
			return null;
		return switch selected.call.arguments {
			case [EString(library), EString(primitive), EInt(arity)]: {library: library, primitive: primitive, arity: arity};
			case _: null;
		};
	}
}
