/** Exact loaded module identity, projection, and resolved imports for startup ordering. */
typedef TypedStartupModule = {
	final moduleIdentity:String;
	final projection:TypedBackendModuleProjection;
	final importedClasses:Array<TyNominalTypeId>;
}

/**
	Order loaded modules separately from classes used by initializer expressions.
	All loaded classes remain present. Module references include nonexecuting bodies;
	class dependencies follow field initialization and the bodies of called helpers.
	A stored field closure is deferred, but references inside a called helper remain
	dependencies even in dead branches or unused local closures, as observed with the supported upstream native targets.
	The result is an order of classes, not permission to omit unsupported startup work.
 */
class TypedStaticStartupOrder {
	final assertCurrent:Void->Void;
	final classes = new haxe.ds.StringMap<TypedBackendClassProjection>();
	final methods = new haxe.ds.StringMap<TypedBackendFunctionProjection>();
	final moduleClasses = new haxe.ds.StringMap<Array<String>>();
	final moduleDependencies = new haxe.ds.StringMap<Array<String>>();
	final ordered:Array<TypedBackendClassProjection> = [];
	final visitedClasses = new haxe.ds.StringMap<Bool>();
	final visitedMethods = new haxe.ds.StringMap<Bool>();

	public function new(input:{modules:Array<TypedStartupModule>, assertCurrent:Void->Void}) {
		assertCurrent = input.assertCurrent;
		assertCurrent();
		final modules = input.modules.copy();
		for (module in modules) {
			if (!moduleClasses.exists(module.moduleIdentity)) {
				moduleClasses.set(module.moduleIdentity, []);
				moduleDependencies.set(module.moduleIdentity, []);
			}
			for (owner in module.projection.getClasses()) {
				final identity = owner.requireSemanticFacts().getClassIdentity();
				if (classes.exists(identity))
					throw "startup order repeats a class identity";
				classes.set(identity, owner);
				moduleClasses.get(module.moduleIdentity).push(identity);
				for (method in owner.getFunctions())
					methods.set(method.getStableIdentity(), method);
			}
		}
		for (module in modules) {
			function dependency(identity:String):Void {
				final selected = classes.get(identity);
				if (selected == null)
					throw "startup dependency has no loaded class: " + identity;
				final provider = selected.requireSemanticFacts().getModuleIdentity();
				final dependencies = moduleDependencies.get(module.moduleIdentity);
				if (provider != module.moduleIdentity && dependencies.indexOf(provider) < 0)
					dependencies.push(provider);
			}
			for (imported in module.importedClasses)
				dependency(imported.getCanonicalName());
			for (owner in module.projection.getClasses()) {
				final facts = owner.requireSemanticFacts();
				typeDependencies(facts.getSuperType(), dependency);
				for (type in facts.getInterfaceTypes())
					typeDependencies(type, dependency);
				for (field in facts.copyFields())
					typeDependencies(field.semanticType, dependency);
				for (method in owner.getFunctions()) {
					final signature = method.requireSemanticDeclaration().getSignature();
					for (type in signature.getArgs())
						typeDependencies(type, dependency);
					typeDependencies(signature.getReturnType(), dependency);
					catalogDependencies(method.getLocalCatalog(), method.getRuntimeTypeCatalog(), method.getConstructorCatalog(), dependency);
					for (statement in method.getBody())
						TypedBackendSourceWalk.statement(statement, expression -> references(expression, method.findField, dependency, false), _ -> {});
				}
				for (initializer in owner.getFieldInitializers()) {
					catalogDependencies(initializer.getLocalCatalog(), initializer.getRuntimeTypeCatalog(), initializer.getConstructorCatalog(), dependency);
					TypedBackendSourceWalk.expression(initializer.getExpression(),
						expression -> references(expression, initializer.findField, dependency, false));
				}
			}
		}
		final visitedModules = new haxe.ds.StringMap<Bool>();
		function visitModule(identity:String):Void {
			if (visitedModules.exists(identity))
				return;
			visitedModules.set(identity, true);
			final dependencies = moduleDependencies.get(identity);
			if (dependencies == null)
				throw "startup dependency has no loaded module: " + identity;
			for (provider in dependencies)
				visitModule(provider);
			for (owner in moduleClasses.get(identity))
				visitClass(owner);
		}
		for (module in modules)
			visitModule(module.moduleIdentity);
	}

	/** Return the full inventory; callers execute startup methods before ordinary fields. */
	public function getClasses():Array<TypedBackendClassProjection> {
		assertCurrent();
		return ordered.copy();
	}

	static function typeDependencies(type:Null<TyType>, dependency:String->Void):Void {
		if (type == null)
			return;
		final identity = type.getNominalIdentity();
		if (identity != null)
			dependency(identity.getCanonicalName());
		if (type.isNullable())
			typeDependencies(type.getNullableInner(), dependency);
		for (child in type.getTypeArguments().concat(type.getFunctionArguments()).concat(type.getAnonymousFieldTypes()))
			typeDependencies(child, dependency);
		if (type.isFunction())
			typeDependencies(type.getFunctionReturn(), dependency);
	}

	static function catalogDependencies(locals:TypedBackendLocalCatalog, runtime:TypedBackendRuntimeTypeCatalog, constructors:TypedBackendConstructorCatalog,
			dependency:String->Void):Void {
		for (local in locals.getEntries())
			typeDependencies(local.getBinding().getType(), dependency);
		for (entry in constructors.getEntries())
			typeDependencies(entry.getConstructedType(), dependency);
		for (entry in runtime.getEntries()) {
			final identity = entry.getTarget().getDeclarationIdentity();
			if (identity != null)
				dependency(identity.getCanonicalName());
		}
	}

	function references(expression:HxExpr, field:HxExpr->Null<TypedBackendFieldOccurrence>, dependency:String->Void, followCalls:Bool):Void {
		// Typed field occurrences can only own name reads or field selections.
		// Other expressions must not repeatedly validate and scan the enclosing body.
		final selected = switch expression {
			case EIdent(_) | EField(_, _): field(expression);
			case _: null;
		};
		if (selected != null)
			dependency(selected.getField().getOwner().getCanonicalName());
		final call = TypedExactStaticCallSource.decode(expression);
		if (call != null) {
			final method = methods.get(call.declaration);
			if (method == null)
				throw "startup call has no loaded declaration: " + call.declaration;
			dependency(method.requireSemanticDeclaration().getOwner().getCanonicalName());
			if (followCalls)
				visitMethod(method);
		}
	}

	/** A called helper contributes references from its whole typed body, not an execution trace. */
	function visitMethod(method:TypedBackendFunctionProjection):Void {
		if (visitedMethods.exists(method.getStableIdentity()))
			return;
		visitedMethods.set(method.getStableIdentity(), true);
		for (statement in method.getBody())
			TypedBackendSourceWalk.statement(statement, expression -> references(expression, method.findField, visitClass, true), _ -> {});
	}

	function visitInitializer(initializer:TypedBackendFieldInitializerProjection, expression:HxExpr):Void {
		switch expression {
			case ELambda(_, _) | ESourceFunction(_, _, _, _) | EMacroExpr(_, _) | EMacroType(_):
				return;
			case _:
		}
		references(expression, initializer.findField, visitClass, true);
		TypedBackendSourceWalk.expressionChildren(expression, child -> visitInitializer(initializer, child));
	}

	/** Enter a class before following cycles, so a cyclic read can later observe allocated defaults. */
	function visitClass(identity:String):Void {
		if (visitedClasses.exists(identity))
			return;
		final owner = classes.get(identity);
		if (owner == null)
			throw "startup dependency has no loaded class: " + identity;
		visitedClasses.set(identity, true);
		final parent = owner.requireSemanticFacts().getSuperClassIdentity();
		if (parent != null)
			visitClass(parent);
		if (!owner.requireSemanticFacts().getIsExtern()) {
			for (initializer in owner.getFieldInitializers())
				if (initializer.getField().getIsStatic())
					visitInitializer(initializer, initializer.getExpression());
			for (method in owner.getFunctions())
				if (method.requireSemanticDeclaration().getSignature().getName() == "__init__")
					visitMethod(method);
		}
		ordered.push(owner);
	}
}
