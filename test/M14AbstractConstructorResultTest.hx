import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Keep construction result identity separate from the Void completion of an abstract constructor body. */
class M14AbstractConstructorResultTest {
	static function typeSource(source:String, path:String):TypedModule {
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		return TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
	}

	static function main():Void {
		M14CppConstructorApplicationTest.main();
		final root = "test/oracle/abstract_constructor_result_seed";
		final fixture = CppResolvedFixture.load({sourceRoot: root + "/src", mainModule: "Main", requiredModules: ["Array"]});
		final module = fixture.main;
		final arrayProvider = fixture.index.getByFullName("Array");
		if (arrayProvider == null)
			throw "constructor fixture requires its indexed Array provider";
		var applications = 0;
		final typedApplications = new Array<TypedConstructorApplication>();
		function checkExpression(expression:TypedExpr):Void {
			if (expression.getTag() == NewValue) {
				final application = expression.getConstructorApplication();
				if (application == null || application.getDeclaration() != expression.getDeclaration())
					throw "original constructor fixture lost an exact applied constructor";
				final underlying = application.getUnderlyingType();
				if (underlying == null)
					throw "original abstract constructor lost its backing type";
				if (application.getOwnerArguments().length == 1) {
					if (underlying.getNominalIdentity() == null
						|| !underlying.getNominalIdentity().equals(arrayProvider.getIdentity())
						|| underlying.getTypeArguments()[0].getSemanticKey() != "primitive:String"
						|| application.getParameterTypes()[0].getSemanticKey() != "primitive:String")
						throw "applied constructor lost the real Array<String> provider or String argument";
				} else if (underlying.getSemanticKey() != "primitive:Int") {
					throw "primitive constructor annotation changed its underlying Int";
				}
				applications++;
				typedApplications.push(application);
			}
			for (child in expression.getExpressions())
				checkExpression(child);
		}
		function checkStatement(statement:TypedStmt):Void {
			for (expression in statement.getExpressions())
				checkExpression(expression);
			for (child in statement.getStatements())
				checkStatement(child);
		}
		for (cls in module.getTypedClasses())
			if (HxClassDecl.getName(cls.getSourceDeclaration()) == "Main")
				for (fn in cls.getFunctions())
					for (statement in fn.getBody().getStatements())
						checkStatement(statement);
		if (applications != 6)
			throw "original fixture did not verify all six applied constructors";
		final remainingApplications = typedApplications.copy();
		for (cls in module.getBackendProjection().getClasses())
			if (HxClassDecl.getName(cls.getDeclaration()) == "Main")
				for (fn in cls.getFunctions())
					for (entry in fn.getConstructorCatalog().getEntries())
						if (!remainingApplications.remove(fn.requireConstructor(entry.getExpression()).requireApplication()))
							throw "original fixture projected an unknown or repeated constructor application";
		if (remainingApplications.length != 0)
			throw "original fixture lost a constructor application during backend projection";
		var constructors = 0;
		for (cls in module.getTypedClasses()) {
			if (!Std.isOfType(cls.getSemanticInfo(), TyAbstractInfo))
				continue;
			for (fn in cls.getFunctions()) {
				final declaration = fn.getDeclaration();
				if (declaration.getSignature().getName() != "new")
					continue;
				if (fn.getEnvironment().getReturnType().getSemanticKey() != "primitive:Void")
					throw "abstract constructor body must complete with Void: " + declaration.getIdentity().getCanonicalKey();
				final result = declaration.getSignature().getReturnType();
				if (result.getNominalIdentity() == null
					|| result.getNominalIdentity().getCanonicalName() != cls.getSemanticInfo().getFullName())
					throw "constructor declaration lost its exact abstract result";
				final facts = new TypedBackendClassSemanticFacts(cls.getSemanticInfo(), null, cls.getFunctions());
				if (facts.getTypeParameterIds().length != 0)
					switch facts.getNominalKind() {
						case AbstractValue(underlying):
							if (underlying.getNominalIdentity() == null
								|| !underlying.getNominalIdentity().equals(arrayProvider.getIdentity()))
								throw "constructor fixture requires the actual Array declaration";
							final parameters = facts.getTypeParameterIds();
							final arguments = underlying.getTypeArguments();
							if (parameters.length != 1
								|| arguments.length != 1
								|| arguments[0].getTypeParameterIdentity() == null
								|| arguments[0].getTypeParameterIdentity().getCanonicalKey() != parameters[0].getCanonicalKey())
								throw "constructor backing lost its exact owner binder";
							for (applied in [TyType.fromHintText("String"), TyType.fromHintText("Int")]) {
								final bindings = TyTypeSubstitution.bind(parameters, [applied], facts.getClassIdentity());
								final backing = TyTypeSubstitution.apply(underlying, bindings);
								if (!backing.getNominalIdentity().equals(arrayProvider.getIdentity())
									|| backing.getTypeArguments()[0].getSemanticKey() != applied.getSemanticKey())
									throw "applied constructor backing lost provider or argument identity";
							}
						case _:
							throw "generic constructor fixture lost its abstract backing type";
					}
				final method = facts.findMethod(declaration.getIdentity().getCanonicalKey());
				if (method == null || method.returnTypeIdentity != result.getSemanticKey())
					throw "published constructor result differs from its typed declaration";
				constructors++;
			}
		}
		if (constructors != 6)
			throw "constructor fixture did not check every annotation and generic case";
		var rejected = false;
		try {
			final invalid = typeSource('class Main {} abstract Invalid(Int) { public function new(value:Int):Invalid { this = value; return 1; } }',
				"InvalidConstructor.hx");
			invalid.getBackendProjection();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf("constructor body must complete with Void") < 0)
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "value-returning constructor body was accepted";
		Sys.println("ABSTRACT_CONSTRUCTOR_RESULTS:PASS");
		final output = ".tmp/abstract-constructor-result-candidate";
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		final result = CppTargetCore.emit(program, new BackendContext(output, null, "Main", true, true, fixture.defines));
		if (!result.builtExecutable)
			throw "abstract constructor contract requires a native executable";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent(root + "/expected.stdout"))
			throw "native abstract construction differs from upstream: " + stdout + stderr;
		Sys.println("ABSTRACT_CONSTRUCTOR_NATIVE:PASS");
	}
}
