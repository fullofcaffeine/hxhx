import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Compare authored recursive record behavior with an independent upstream runtime. */
class M14RecursiveTypedefRuntimeTest {
	static function main():Void {
		final root = "test/recursive_typedef_runtime";
		final output = JsRuntimeFixture.reserveOutput();
		final expected = sys.io.File.getContent(root + "/expected.stdout");
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run(compiler == null ? "node_modules/.bin/haxe" : compiler,
			["-cp", root, "-main", "Main", "-js", output + "/upstream.js"]);
		if (@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("node", [output + "/upstream.js"]) != expected)
			throw "upstream recursive record output differs: " + output;
		Sys.println("RECURSIVE_TYPEDEF_RUNTIME_UPSTREAM:PASS");
		final args = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "js"
		});
		final module = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(sys.io.File.getContent(root + "/Main.hx"), root + "/Main.hx"));
		final index = TyperIndex.buildHeaders([module]);
		final defines = Stage3SetupSupport.buildDefinesMap([], "js", "js-native");
		final loader = new ModuleLoader(paths, defines, index, null, false);
		loader.markResolvedAlready([module]);
		final typed = TyperStage.typeResolvedModule(module, index, loader, true);
		consumerFacts(typed);
		final program = MacroStage.expandProgram(TypedAbstractOperatorLowering.lowerModules([typed], index), []);
		final script = output + "/candidate.js";
		new backend.js.JsBackend().emit(program, new backend.BackendContext(output, script, "Main", true, false, defines));
		if (@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("node", [script]) != expected)
			throw "candidate recursive record output differs: " + output;
		Sys.println("RECURSIVE_TYPEDEF_RUNTIME:PASS " + output);
		literalContracts();
	}

	/** Runtime JavaScript can work even after type erasure; require exact checked facts before emission. */
	static function consumerFacts(module:TypedModule):Void {
		var indexed = 0;
		var chained = 0;
		var recursiveFields = 0;
		function expression(value:TypedExpr):Void {
			final children = value.getExpressions();
			if (value.getTag() == ArrayAccess) {
				final type = TyAliasExpansion.revealNonNullable(value.getType());
				if (type.getNominalIdentity() == null
					|| type.getNominalIdentity().getCanonicalName() != "Array"
					|| type.getTypeArguments().length != 1
					|| type.getTypeArguments()[0].getAliasDefinition() == null)
					throw "recursive index lost its exact collection element";
				indexed++;
			}
			if (value.getTag() == Call && children[0].getTag() == Call) {
				if (!TyAliasExpansion.revealNonNullable(value.getType()).isFunction() || value.getArgumentBinding() == null)
					throw "recursive chained call lost its result or checked arguments";
				chained++;
			}
			if (value.getTag() == FieldRead
				&& children[0].getType().getAliasDefinition() != null
				&& TyAliasExpansion.revealNonNullable(children[0].getType()).isAnonymous()) {
				if (!TypedBackendObjectAccess.supports(value))
					throw "recursive record lost its backend field access contract";
				recursiveFields++;
			}
			for (child in children)
				expression(child);
		}
		function statement(value:TypedStmt):Void {
			for (child in value.getExpressions())
				expression(child);
			for (child in value.getStatements())
				statement(child);
		}
		for (owner in module.getTypedClasses())
			for (fn in owner.getFunctions())
				for (body in fn.getBody().getStatements())
					statement(body);
		if (indexed != 2 || chained != 1 || recursiveFields == 0)
			throw "recursive consumer observer did not cover every requested operation";
		Sys.println("RECURSIVE_CONSUMER_FACTS:PASS");
	}

	/** Source-level checks must reject invalid children at the recursive edge, not only at the outer record. */
	static function literalContracts():Void {
		final root = JsRuntimeFixture.reserveOutput();
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		final cases = [
			{
				name: "omitted optional child",
				type: "Node",
				value: "{value:2}",
				accepted: true
			},
			{
				name: "nested valid child",
				type: "Node",
				value: "{value:2,next:{value:3}}",
				accepted: true
			},
			{
				name: "nested missing payload",
				type: "Node",
				value: "{value:2,next:{}}",
				accepted: false
			},
			{
				name: "nested extra field",
				type: "Node",
				value: "{value:2,next:{value:3,extra:4}}",
				accepted: false
			},
			{
				name: "nested wrong payload",
				type: "Node",
				value: '{value:2,next:{value:"wrong"}}',
				accepted: false
			},
			{
				name: "recursive empty array",
				type: "Branches",
				value: "[]",
				accepted: true
			},
			{
				name: "recursive nested arrays",
				type: "Branches",
				value: "[[[]]]",
				accepted: true
			},
			{
				name: "recursive wrong array element",
				type: "Branches",
				value: "[[1]]",
				accepted: false
			},
			{
				name: "recursive chained callable",
				type: "Step",
				value: "step(1)(2)",
				accepted: true
			},
			{
				name: "recursive wrong call argument",
				type: "Step",
				value: 'step(1)("wrong")',
				accepted: false
			}
		];
		for (input in cases) {
			final source = "typedef Node={final value:Int; final ?next:Node;}; typedef Branches=Array<Branches>; typedef Step=Int->Step; "
				+ "class Main { static function step(value:Int):Step { return step; } static function main():Void { var node:"
				+ input.type
				+ "="
				+ input.value
				+ "; } }";
			final path = root + "/Main.hx";
			sys.io.File.saveContent(path, source);
			final upstream = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", [
				"30",
				compiler == null ? "node_modules/.bin/haxe" : compiler,
				"-cp",
				root,
				"-main",
				"Main",
				"-js",
				root + "/upstream.js"
			]);
			final stdout = upstream.stdout.readAll().toString();
			final stderr = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			if ((code == 0) != input.accepted || (code != 0 && code != 1))
				throw "upstream recursive literal differs for " + input.name + ": " + stdout + stderr;
			final args = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
			final paths = Stage3SetupSupport.projectClassPaths({
				explicitPaths: [root],
				libraries: [],
				cwd: Sys.getCwd(),
				standardRoot: Stage1Args.getStandardLibraryRoot(args),
				targetDefine: "js"
			});
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			final index = TyperIndex.buildHeaders([module]);
			final defines = Stage3SetupSupport.buildDefinesMap([], "js", "js-native");
			final loader = new ModuleLoader(paths, defines, index, null, false);
			loader.markResolvedAlready([module]);
			var accepted = true;
			try {
				TyperStage.typeResolvedModule(module, index, loader, true);
			} catch (error:TyperError) {
				accepted = false;
				if (input.accepted)
					throw error;
			}
			if (accepted != input.accepted)
				throw "candidate recursive literal differs for " + input.name;
			Sys.println("RECURSIVE_LITERAL_CASE:PASS " + input.name);
		}
	}
}
