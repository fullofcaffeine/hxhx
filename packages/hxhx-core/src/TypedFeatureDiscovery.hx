import haxe.ds.StringMap;

/**
	Discover feature definitions in exact retained declarations of one typed program.
	The retention owner supplies declaration objects, not names or copied bodies.
	Both feature branches are scanned before runtime selection, matching upstream's
	compile-time discovery behavior. This class does not decide DCE reachability.
 */
class TypedFeatureDiscovery {
	final program:MacroExpandedProgram;
	final names:Array<String>;

	public function new(input:TypedFeatureRoots.TypedFeatureRootSet) {
		program = input.program;
		program.assertTypedBodyRevisionsCurrent();
		final ownedClasses = new haxe.ds.ObjectMap<TypedClass, TypedModule>();
		for (module in program.getTypedModules())
			for (owner in module.getTypedClasses())
				ownedClasses.set(owner, module);
		final functionOwners = new haxe.ds.ObjectMap<TypedFunction, String>();
		final fieldOwners = new haxe.ds.ObjectMap<TyFieldInfo, String>();
		final initializers = new haxe.ds.ObjectMap<TyFieldInfo, TypedFieldInitializer>();
		final featureOwners = new StringMap<TypedClass>();
		final active = new StringMap<Bool>();
		for (owner in input.classes) {
			final module = ownedClasses.get(owner);
			if (module == null || owner.getSemanticInfo() == null)
				throw "retained feature class is not an exact semantic provider in this program";
			final info = owner.getSemanticInfo();
			final packagePath = module.getEnv().getPackagePath();
			// The feature protocol uses package plus declared type name, even for a
			// secondary type whose exact semantic identity also contains its module.
			final protocolName = (packagePath.length == 0 ? "" : packagePath + ".") + info.getShortName();
			final previous = featureOwners.get(protocolName);
			if (previous != null && previous != owner)
				throw "distinct retained types have an ambiguous feature protocol name: " + protocolName;
			featureOwners.set(protocolName, owner);
			active.set(protocolName + ".*", true);
			for (fn in owner.getFunctions())
				functionOwners.set(fn, protocolName);
			for (field in info.getFieldInfos())
				fieldOwners.set(field, protocolName);
			for (initializer in owner.getFieldInitializers())
				initializers.set(initializer.getField(), initializer);
		}
		function expression(node:TypedExpr):Void {
			if (node.getTag() == MacroExpr || node.getTag() == MacroType)
				return;
			if (node.getTag() == FeatureDefinition)
				active.set(node.getTexts()[0], true);
			for (child in node.getExpressions())
				expression(child);
		}
		function statement(node:TypedStmt):Void {
			for (child in node.getExpressions())
				expression(child);
			for (child in node.getStatements())
				statement(child);
		}
		for (fn in input.functions) {
			final owner = functionOwners.get(fn);
			final declaration = fn.getDeclaration();
			if (owner == null || declaration == null)
				throw "retained feature function is not an exact declaration of a retained class";
			active.set(owner + "." + declaration.getSignature().getName(), true);
			for (body in fn.getBody().getStatements())
				statement(body);
		}
		for (field in input.fields) {
			final owner = fieldOwners.get(field);
			if (owner == null)
				throw "retained feature field is not an exact declaration of a retained class";
			active.set(owner + "." + field.getName(), true);
			final initializer = initializers.get(field);
			if (initializer != null)
				expression(initializer.getExpression());
		}
		names = [for (name in active.keys()) name];
		names.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
	}

	/**
		Scan every supplied declaration for component checks. This is not a DCE policy:
		upstream can emit unused SDK methods without activating their feature definitions,
		even with DCE disabled. Production callers must select feature-relevant declarations.
	**/
	public static function allRetained(program:MacroExpandedProgram):TypedFeatureDiscovery {
		final classes = [
			for (module in program.getTypedModules())
				for (owner in module.getTypedClasses())
					owner
		];
		return new TypedFeatureDiscovery({
			program: program,
			classes: classes,
			functions: [for (owner in classes) for (fn in owner.getFunctions()) fn],
			fields: [
				for (owner in classes)
					if (owner.getSemanticInfo() != null) for (field in owner.getSemanticInfo().getFieldInfos()) field
			]
		});
	}

	/** Decisions cannot be reused for an equal-looking foreign or retyped program. */
	public function namesFor(owner:MacroExpandedProgram):Array<String> {
		if (owner != program)
			throw "feature discovery belongs to another typed program";
		program.assertTypedBodyRevisionsCurrent();
		return names.copy();
	}
}
