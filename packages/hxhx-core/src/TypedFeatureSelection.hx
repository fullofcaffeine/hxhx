import haxe.ds.StringMap;

/**
	Apply a completed feature decision to an immutable typed program.
	The caller owns discovery and retention policy. This pass only selects runtime
	operands; it must not discover definitions from the branches it chooses.
	Names are the feature protocol's literal keys, not inferred declaration identities.
 */
function lower(program:MacroExpandedProgram, activeFeatures:Array<String>):MacroExpandedProgram {
	program.assertTypedBodyRevisionsCurrent();
	final active = new StringMap<Bool>();
	for (name in activeFeatures) {
		if (name == null)
			throw "feature selection requires literal feature names";
		active.set(name, true);
	}
	function expression(node:TypedExpr):TypedExpr {
		final children = node.getExpressions();
		switch node.getTag() {
			case MacroExpr | MacroType:
				return node;
			case FeatureDefinition:
				return expression(children[0]);
			case FeatureSelection:
				if (active.exists(node.getTexts()[0]))
					return expression(children[0]);
				return children.length == 2 ? expression(children[1]) : TypedExpr.sourceGroup([], TyType.fromHintText("Void"), node.getPosition());
			case _:
		}
		final replaced = [for (child in children) expression(child)];
		for (index in 0...children.length)
			if (children[index] != replaced[index])
				return node.withExpressions(replaced);
		return node;
	}
	function statement(node:TypedStmt):TypedStmt {
		final expressions = node.getExpressions();
		final statements = node.getStatements();
		final replacedExpressions = [for (child in expressions) expression(child)];
		final replacedStatements = [for (child in statements) statement(child)];
		for (index in 0...expressions.length)
			if (expressions[index] != replacedExpressions[index])
				return node.withChildren(replacedExpressions, replacedStatements);
		for (index in 0...statements.length)
			if (statements[index] != replacedStatements[index])
				return node.withChildren(replacedExpressions, replacedStatements);
		return node;
	}
	var changedProgram = false;
	final modules = [
		for (module in program.getTypedModules()) {
			var changedModule = false;
			final classes = [
				for (owner in module.getTypedClasses()) {
					var changedClass = false;
					final functions = [
						for (fn in owner.getFunctions()) {
							final statements = fn.getBody().getStatements();
							final replacements = [for (entry in statements) statement(entry)];
							var changed = false;
							for (index in 0...statements.length)
								if (statements[index] != replacements[index])
									changed = true;
							if (changed) changedClass = true;
							changed ? fn.withBody(new TypedFunctionBody(replacements, fn.getBody().getSourceFingerprint())) : fn;
						}
					];
					final fields = [
						for (field in owner.getFieldInitializers()) {
							final replacement = expression(field.getExpression());
							final changed = replacement != field.getExpression();
							if (changed) changedClass = true;
							changed ? new TypedFieldInitializer(field.getField(), replacement) : field;
						}
					];
					if (changedClass) changedModule = true;
					changedClass ? owner.withMembers({functions: functions, fields: owner.getFields(), initializers: fields}) : owner;
				}
			];
			if (changedModule) changedProgram = true;
			changedModule ? module.withTypedClasses(classes) : module;
		}
	];
	return changedProgram ? new MacroExpandedProgram(modules, program.macroMode, program.getGeneratedOcamlModules()) : program;
}
