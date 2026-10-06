/** Inspect real-provider literal facts before target storage can hide a contextual typing error. */
class M14ContextualMapEntriesTest {
	public static function run():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/shared_map_literal_typing_seed/entries",
			mainModule: "Entries",
			requiredModules: ["haxe.ds.Map", "Array"]
		});
		final observed = new haxe.ds.StringMap<Int>();
		function expression(value:TypedExpr, expected:TyType, name:String):Void {
			if (value.getTag() == ArrayDecl) {
				observed.set(name, (observed.exists(name) ? observed.get(name) : 0) + 1);
				if (value.getType().getSemanticKey() != expected.getSemanticKey())
					throw name + " literal type " + value.getType().getSemanticKey() + " differs from " + expected.getSemanticKey();
				if (["returned", "local", "assigned", "argument"].indexOf(name) >= 0) {
					final entry = value.getExpressions()[0];
					if (entry.getExpressions()[1].getType().getSemanticKey() != "primitive:Float")
						throw name + " erased the Float operand before conversion";
				}
			}
			for (child in value.getExpressions())
				expression(child, expected, name);
		}
		function statements(values:Array<TypedStmt>, expected:TyType, name:String):Void {
			for (statement in values) {
				for (value in statement.getExpressions())
					expression(value, expected, name);
				statements(statement.getStatements(), expected, name);
			}
		}
		for (cls in fixture.main.getTypedClasses()) {
			for (initializer in cls.getFieldInitializers())
				expression(initializer.getExpression(), initializer.getField().getType(), "field");
			for (fn in cls.getFunctions()) {
				final name = HxFunctionDecl.getName(fn.getSourceDeclaration());
				if (name != "take")
					statements(fn.getBody().getStatements(), fn.getEnvironment().getReturnType(), name);
			}
		}
		for (name in [
			"field",
			"returned",
			"local",
			"assigned",
			"argument",
			"nested",
			"generic",
			"callback",
			"mixed",
			"ordinary"
		])
			if (!observed.exists(name) || observed.get(name) != 1)
				throw "missing exact literal observation for " + name;
		final program = new backend.cpp.CppTypedProgramProjection(new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules,
			fixture.index), false));
		var projected = 0;
		for (fn in program.requireClass(program.requireClassIdentity("Entries")).getFunctions()) {
			final name = fn.requireSemanticDeclaration().getSignature().getName();
			if (["returned", "local", "assigned", "argument"].indexOf(name) < 0)
				continue;
			for (statement in fn.getBody())
				TypedBackendSourceWalk.statement(statement, value -> {
					if (value.match(EArrayDecl(_))) {
						final aggregate = fn.requireAggregate(value);
						if (!aggregate.getType().getTypeArguments()[1].isDynamic()
							|| aggregate.getMapEntries().length != 1
							|| aggregate.getMapEntries()[0].valueType.getSemanticKey() != "primitive:Float")
							throw name + " projection lost distinct storage and operand types";
						projected++;
					}
				}, _ -> {});
		}
		if (projected != 4)
			throw "Map projection did not cover all four Float entry contexts";
		program.assertCurrent();
		for (name in ["InvalidValue", "InvalidKey", "InvalidNested"]) {
			final path = "test/oracle/shared_map_literal_typing_seed/entries/" + name + ".hx";
			final resolved = new ResolvedModule(name, path, ParserStage.parse(sys.io.File.getContent(path), path));
			fixture.index.addResolvedModule(resolved);
			var rejected = false;
			try {
				TyperStage.typeResolvedModule(resolved, fixture.index, null, true);
			} catch (error:TyperError) {
				if (error.message.indexOf("not compatible") < 0)
					throw error;
				rejected = true;
			}
			if (!rejected)
				throw "incompatible Map entry accepted in " + name;
		}
		Sys.println("CONTEXTUAL_MAP_ENTRIES:PASS");
	}

	static function main():Void
		run();
}
