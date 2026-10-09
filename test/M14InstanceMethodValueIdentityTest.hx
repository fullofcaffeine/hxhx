/** Explicit method reads must retain exact declarations, callable types and provider dependencies. */
class M14InstanceMethodValueIdentityTest {
	static function parse(name:String, source:String):ResolvedModule {
		return new ResolvedModule(name, name + ".hx", ParserStage.parse(source, name + ".hx"));
	}

	static function main():Void {
		final providers = [
			for (name in ["Provider", "Other"])
				parse(name, "class " + name + " { public var count:Int; public function run(value:Int):String { return \"result\"; } }")
		];
		final consumer = parse("Consumer",
			"class Consumer { static function first(receiver:Provider):Void { final selected = receiver.run; final data = receiver.count; } static function second(receiver:Other):Void { final selected = receiver.run; } }");
		final index = TyperIndex.build(providers.concat([consumer]));
		final modules = [
			for (resolved in providers.concat([consumer]))
				TyperStage.typeResolvedModule(resolved, index)
		];
		final dependencies = CompilerDependencyCollector.collect(modules, index);
		var methods = 0;
		var fields = 0;
		function expression(node:TypedExpr):Void {
			if (node.getTag() == FieldRead) {
				final name = node.getTexts()[0];
				if (name == "run") {
					final receiver = node.getExpressions()[0];
					final provider = index.getByFullName(receiver.getType().getNominalIdentity().getCanonicalName());
					final selected = provider.declarationForSignature(provider.instanceMethod("run"));
					if (node.getDeclaration() != selected || node.getFieldInfo() != null || receiver.getTag() != LocalRead)
						throw "instance method read lost its exact declaration or receiver";
					final callable = node.getType();
					if (!callable.isFunction()
						|| callable.getFunctionArguments().length != 1
						|| callable.getFunctionArguments()[0].getSemanticKey() != "primitive:Int"
						|| callable.getFunctionReturn().getSemanticKey() != "primitive:String")
						throw "instance method read lost its callable signature";
					var dependency = false;
					for (edge in dependencies.getEdges())
						if (edge.consumerModule == "Consumer"
							&& edge.providerModule == provider.getModulePath()
							&& edge.factIdentity == "declaration:" + selected.getIdentity().getCanonicalKey())
							dependency = true;
					if (!dependency)
						throw "instance method value lost its exact provider dependency";
					if (node.withExpressions(node.getExpressions()).getDeclaration() != selected)
						throw "instance method rewrite lost its selected declaration";
					methods++;
				} else if (name == "count") {
					if (node.getDeclaration() != null || node.getFieldInfo() == null)
						throw "ordinary data field became a method selection";
					fields++;
				}
			}
			for (child in node.getExpressions())
				expression(child);
		}
		function statement(node:TypedStmt):Void {
			for (child in node.getExpressions())
				expression(child);
			for (child in node.getStatements())
				statement(child);
		}
		for (owner in modules[2].getTypedClasses())
			for (fn in owner.getFunctions())
				for (body in fn.getBody().getStatements())
					statement(body);
		if (methods != 2 || fields != 1)
			throw "instance method identity fixture did not inspect its required reads";
		Sys.println("INSTANCE_METHOD_VALUE_IDENTITY:PASS");
	}
}
