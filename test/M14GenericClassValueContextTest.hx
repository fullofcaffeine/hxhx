import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/**
	A generic factory receives a fresh instance context from each class-value use.
	Upstream compilation supplies the acceptance contract. Shared typed assertions
	also check the call and operand types, because a written local annotation can
	hide an incorrectly erased result until a later lowering pass.
 */
class M14GenericClassValueContextTest {
	static function main():Void {
		factContracts();
		final cases = [
			{name: "literal", body: "var result:Array<String> = Factory.create(Array);", accepted: true},
			{name: "parenthesized", body: "var result:Array<String> = Factory.create((Array));", accepted: true},
			{name: "inferred_alias", body: "var cls = Array; var result:Array<String> = Factory.create(cls);", accepted: true},
			{name: "erased_destination", body: "var cls = Array; erase(cls); erase(Array); var result:Array<String> = Factory.create(cls);", accepted: true},
			{name: "null_write", body: "var cls = Array; cls = null; var result:Array<String> = Factory.create(cls);", accepted: true},
			{name: "independent", body: "var a:Array<Int> = Factory.create(Array); var b:Array<String> = Factory.create(Array);", accepted: true},
			{name: "shared_alias", body: "var cls = Array; var a:Array<Int> = Factory.create(cls); var b:Array<String> = Factory.create(cls);", accepted: true},
			{
				name: "alias_of_alias",
				body: "var cls = Array; var copy = cls; var a:Array<Int> = Factory.create(copy); var b:Array<String> = Factory.create(cls);",
				accepted: true
			},
			{name: "nominal_literal", body: "var result:Box<String> = Factory.create(Box);", accepted: true},
			{name: "nominal_alias", body: "var cls = Box; var a:Box<Int> = Factory.create(cls); var b:Box<String> = Factory.create(cls);", accepted: true},
			{name: "later_context", body: "var result = Factory.create(Array); take(result);", accepted: true},
			{name: "generic_result", body: "var result:Array<String> = make();", accepted: true},
			{name: "explicit_concrete", body: "var cls:Class<Array<String>> = Array; var result:Array<String> = Factory.create(cls);", accepted: true},
			{name: "explicit_erased", body: "var cls:Class<Array<Dynamic>> = Array; var result:Array<String> = Factory.create(cls);", accepted: false},
			{name: "typed_cast", body: "var cls = (cast Array : Class<Array<Dynamic>>); var result:Array<String> = Factory.create(cls);", accepted: false},
			{name: "shadowed", body: "var Array:Class<Array<Dynamic>> = null; var result:Array<String> = Factory.create(Array);", accepted: false},
			{
				name: "erased_write",
				body: "var cls = Array; var erased:Class<Array<Dynamic>> = Array; cls = erased; var result:Array<String> = Factory.create(cls);",
				accepted: false
			},
			{name: "different_write", body: "var cls = Array; cls = String; var result:Array<String> = Factory.create(cls);", accepted: false},
			{name: "array_storage", body: "var source:Array<Dynamic> = []; var result:Array<String> = source;", accepted: false}
		];
		final failures = new Array<String>();
		for (entry in cases) {
			final root = ".tmp/generic-class-value-context/" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			final source = "extern class Factory { static function create<T>(cls:Class<T>):T; }"
				+ "class Box<T> { public function new() {} }"
				+ "class Main { static function take(value:Array<String>):Void {} static function erase(value:Class<Dynamic>):Void {} "
				+ (entry.name == "generic_result" ? "static function make<T>():Array<T> { return Factory.create(Array); }" : "")
				+ "static function main():Void {"
				+ entry.body
				+ "} }";
			sys.io.File.saveContent(path, source);
			final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
			final upstream = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler,
				["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
			final stdout = upstream.stdout.readAll().toString();
			final stderr = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			if ((code == 0) != entry.accepted || (!entry.accepted && stderr.indexOf("should be") < 0))
				throw "upstream class-value context changed: " + entry.name + stdout + stderr;
			Sys.println("GENERIC_CLASS_VALUE_UPSTREAM:PASS " + entry.name);
			final arguments = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
			final paths = Stage3SetupSupport.projectClassPaths({
				explicitPaths: [root],
				libraries: [],
				cwd: Sys.getCwd(),
				standardRoot: Stage1Args.getStandardLibraryRoot(arguments),
				targetDefine: "js"
			});
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			final index = TyperIndex.buildHeaders([module]);
			final loader = new ModuleLoader(paths, Stage3SetupSupport.buildDefinesMap([], "js", "js-native"), index, null, false);
			loader.markResolvedAlready([module]);
			var typed:Null<TypedModule> = null;
			var rejection:Null<String> = null;
			try {
				typed = TyperStage.typeResolvedModule(module, index, loader, true);
				TypedBodyInvariant.assertClasses(typed.getTypedClasses());
				TypedAbstractOperatorLowering.lowerModules([typed], index)[0].getBackendProjection();
			} catch (error:haxe.Exception) {
				rejection = error.message;
			}
			if (entry.accepted && rejection != null) {
				failures.push(entry.name + ": rejected valid source: " + rejection);
				continue;
			}
			if (!entry.accepted) {
				if (rejection == null)
					failures.push(entry.name + ": accepted incompatible class or array storage");
				else if (rejection.indexOf("compatible") < 0 && rejection.indexOf("conflict") < 0 && rejection.indexOf("conversion") < 0)
					failures.push(entry.name + ": unrelated rejection: " + rejection);
				else
					Sys.println("GENERIC_CLASS_VALUE_REJECTION:PASS " + entry.name);
				continue;
			}
			try {
				checkCalls(typed, entry.name);
				Sys.println("GENERIC_CLASS_VALUE_CONTEXT:PASS " + entry.name);
			} catch (error:haxe.Exception) {
				failures.push(entry.name + ": " + error.message);
			}
		}
		if (failures.length > 0)
			throw "generic class-value failures:\n" + failures.join("\n");
		runtime();
	}

	/** Check descriptor transport through an authored factory, independently of compile-only extern tests. */
	static function runtime():Void {
		final root = "test/generic_class_values";
		final source = sys.io.File.getContent(root + "/Main.hx");
		final expected = sys.io.File.getContent(root + "/expected.stdout");
		final output = ".tmp/generic-class-value-runtime";
		sys.FileSystem.createDirectory(output);
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		run(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "-js", output + "/upstream.js"]);
		if (run("node", [output + "/upstream.js"]) != expected)
			throw "upstream generic class-value runtime differs";
		final args = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "js"
		});
		final module = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(source, root + "/Main.hx"));
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader(paths, Stage3SetupSupport.buildDefinesMap([], "js", "js-native"), index, null, false);
		loader.markResolvedAlready([module]);
		final typed = TyperStage.typeResolvedModule(module, index, loader, true);
		JsRuntimeFixture.assertRuntime(TypedAbstractOperatorLowering.lowerModules([typed], index)[0], "Main", expected);
		Sys.println("GENERIC_CLASS_VALUE_RUNTIME:PASS");
	}

	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "class-value observer failed: " + stdout + stderr;
		return stdout;
	}

	/** Check both sides of the call contract; local annotations alone are not result evidence. */
	static function checkCalls(module:TypedModule, caseName:String):Void {
		var calls = 0;
		var genericElement:Null<TyType> = null;
		function expression(value:TypedExpr):Void {
			final declaration = value.getDeclaration();
			if (value.getTag() == Call && declaration != null && declaration.getOwner().getCanonicalName() == "Main.Factory") {
				final element = calls == 0
					&& (caseName == "independent" || caseName == "shared_alias" || caseName == "alias_of_alias" || caseName == "nominal_alias") ? "Int" : "String";
				final instance = TyType.nominal(new TyNominalTypeId(StringTools.startsWith(caseName, "nominal_") ? "Main.Box" : "Array"),
					[genericElement == null ? TyType.fromHintText(element) : genericElement]);
				if (value.getType().getSemanticKey() != instance.getSemanticKey())
					throw "factory result differs: " + value.getType().getSemanticKey() + " expected " + instance.getSemanticKey();
				final named = value.getNamedArguments();
				if (named == null)
					throw "factory lost its checked named call";
				final arguments = named.getArguments();
				final inputs = arguments.getOperandTypes();
				final expected = TyType.nominal(new TyNominalTypeId("Class"), [instance]);
				if (inputs.length != 1
					|| inputs[0].getSemanticKey() != expected.getSemanticKey()
					|| arguments.getFunctionType().getFunctionReturn().getSemanticKey() != instance.getSemanticKey())
					throw "factory signature and selected class context disagree";
				calls++;
			}
			for (child in value.getExpressions())
				expression(child);
		}
		function statement(value:TypedStmt):Void {
			for (child in value.getExpressions())
				expression(child);
			for (child in value.getStatements())
				statement(child);
		}
		for (owner in module.getTypedClasses())
			if (owner.getSemanticInfo().getIdentity().getCanonicalName() == "Main")
				for (fn in owner.getFunctions())
					if (fn.getDeclaration().getSignature().getName() == "main" || caseName == "generic_result") {
						genericElement = fn.getDeclaration()
							.getTypeParameterIds()
							.length == 0 ? null : TyType.typeParameter(fn.getDeclaration().getTypeParameterIds()[0]);
						for (body in fn.getBody().getStatements())
							statement(body);
					}
		final expectedCalls = caseName == "independent" || caseName == "shared_alias" || caseName == "alias_of_alias" || caseName == "nominal_alias" ? 2 : 1;
		if (calls != expectedCalls)
			throw "factory observer did not inspect every authored call";
	}

	/** Exact declarations and lexical uses survive copying and sealing; erased types grant no scheme permission. */
	static function factContracts():Void {
		final source = "class Box<T> {} class Other<T> {} class Main {}";
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final index = TyperIndex.build([module]);
		final target = new TypedRuntimeTypeTarget(Nominal(new TyNominalTypeId("Main.Box")));
		final scheme = TyClassValueScheme.select(target, index);
		final other = TyClassValueScheme.select(new TypedRuntimeTypeTarget(Nominal(new TyNominalTypeId("Main.Other"))), index);
		final type = TyType.classValue(scheme);
		final concrete = scheme.application([TyType.fromHintText("String")]);
		final erased = scheme.application([TyType.fromHintText("Dynamic")]);
		if (type.getSemanticKey() == erased.getSemanticKey()
			|| type.hasUnknownComponent()
			|| TyTypeSubstitution.freeParameterIdentities(type).length != 0
			|| TyTypeSubstitution.apply(type, new haxe.ds.StringMap()).getSemanticKey() != type.getSemanticKey()
			|| TyAssignmentCompatibility.classify(type, erased, Unchecked) != Incompatible)
			throw "class scheme lost its binding scope or became an erased handle";
		final literal = TypedExpr.runtimeTypeValue(target, null);
		final retained = TyClassValueScheme.convert(literal, type);
		final applied = TyClassValueScheme.convert(retained, concrete);
		if (retained == null
			|| applied == null
			|| !applied.isRepresentationPreservingCast()
			|| applied.getExpressions()[0] != retained
			|| retained.getExpressions()[0] != literal
			|| TyClassValueScheme.convert(TypedExpr.localRead("erased", erased, null), concrete) != null
			|| TyClassValueScheme.convert(literal, TyType.classValue(other)) != null)
			throw "class application lost its original operand or admitted unrelated evidence";
		if (applied.withExpressions([TypedExpr.localRead("erased", erased, null)]).isRepresentationPreservingCast())
			throw "class application retained conversion permission after changing its source type";
		if (CompilerTypedTreeRevision.expression("class-value", retained) == CompilerTypedTreeRevision.expression("class-value", literal))
			throw "class scheme did not affect the typed revision";
		final environment = new TyFunctionEnv("class-value", [], [], TyType.unknown(), TyType.unknown());
		final inference = environment.getInference();
		environment.declareLocal("value", type, Variable);
		final use:HxExpr = EIdent("value");
		@:privateAccess inference.classValueTerm(use, scheme, environment);
		if (!inference.constrain([use], [concrete], environment, index))
			throw "class use did not accept its instance context";
		reject(() -> @:privateAccess inference.classValueTerm(use, other, environment), "changed its generic declaration");
		inference.seal(environment.getLocals());
		if (inference.expressionType(use, type, environment).getSemanticKey() != concrete.getSemanticKey()
			|| environment.resolveSymbol("value").getType().getSemanticKey() != type.getSemanticKey())
			throw "class use context changed its reusable alias";
		if (inference.fork().expressionType(use, type, environment).getSemanticKey() != concrete.getSemanticKey())
			throw "sealed fork lost the selected context";
		reject(() -> @:privateAccess inference.classValueTerm(EIdent("value"), scheme, environment), "absent from sealed inference");
		environment.enterLexicalScope();
		environment.declareLocal("value", type, Variable);
		reject(() -> inference.expressionType(use, type, environment), "changed its lexical declaration");
		environment.exitLexicalScope();
		Sys.println("GENERIC_CLASS_VALUE_FACTS:PASS");
	}

	static function reject(action:Void->Void, diagnostic:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(diagnostic) < 0)
				throw error;
			return;
		}
		throw "class-value boundary accepted invalid evidence: " + diagnostic;
	}
}
