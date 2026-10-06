import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** A Dynamic generic destination must preserve the shape and later evidence of an inferred value. */
class M14GenericDynamicInferenceTest {
	/** Failed candidate assignments must not grant fallback to the original solver's variables. */
	static function transactions():Void {
		final pair = new TyNominalTypeId("Pair");
		final integer = TyType.fromHintText("Int");
		final dynamicType = TyType.fromHintText("Dynamic");
		final solver = new TyInferenceSolver("generic-destination-rollback");
		final pending = solver.freshOmittedParameter();
		final actual = TyInferenceTerm.Nominal(pair, [pending, TyInferenceTerm.Known(integer)]);
		if (TyStructuralConstraint.constrainNominalAssignment(null, solver, actual, TyType.nominal(pair, [dynamicType, TyType.fromHintText("String")])))
			throw "generic assignment accepted a conflicting second argument";
		solver.seal();
		if (!solver.published(pending).isUnknown())
			throw "failed generic assignment leaked Dynamic evidence";
		final selection = new TyInferenceSolver("generic-destination-discarded-overload");
		final argument = selection.freshOmittedParameter();
		final discarded = selection.fork();
		if (!TyStructuralConstraint.constrainNominalAssignment(null, discarded, TyInferenceTerm.Nominal(pair, [argument, TyInferenceTerm.Known(integer)]),
			TyType.nominal(pair, [dynamicType, integer])))
			throw "speculative overload could not receive Dynamic evidence";
		selection.seal();
		if (!selection.published(argument).isUnknown())
			throw "discarded overload leaked Dynamic evidence";
		final source = new TyInferenceSolver("generic-destination-foreign");
		final target = new TyInferenceSolver("generic-destination-local");
		var rejected = false;
		try {
			TyStructuralConstraint.constrainNominalAssignment(null, target, TyInferenceTerm.Nominal(pair, [source.fresh(), TyInferenceTerm.Known(integer)]),
				TyType.nominal(pair, [dynamicType, integer]));
		} catch (error:haxe.Exception)
			rejected = error.message == "inference variable belongs to another owner";
		if (!rejected)
			throw "generic assignment accepted a foreign variable";
		final incomplete = new TyInferenceSolver("generic-destination-incomplete");
		final unknown = TyInferenceTerm.Nominal(pair, [TyInferenceTerm.Known(TyType.unknown()), TyInferenceTerm.Known(integer)]);
		TyStructuralConstraint.constrainNominalAssignment(null, incomplete, unknown, TyType.nominal(pair, [dynamicType, integer]));
		rejected = false;
		try
			incomplete.seal()
		catch (error:haxe.Exception)
			rejected = error.message == "inference cannot publish an incomplete concrete type";
		if (!rejected)
			throw "generic destination converted missing concrete facts into Dynamic";
		Sys.println("GENERIC_DYNAMIC_INFERENCE_TRANSACTIONS:PASS");
	}

	static function main():Void {
		transactions();
		for (entry in [
			{
				name: "nested",
				body: "take(wrap([]));",
				accepted: true,
				element: "dynamic",
				calls: 1
			},
			{
				name: "later",
				body: "var items=[];var boxed=wrap(items);take(boxed);var ints:Array<Int>=items;",
				accepted: true,
				element: "primitive:Int",
				calls: 1
			},
			{
				name: "nested_destination",
				body: "takeNested(wrap([]));",
				accepted: true,
				element: "dynamic",
				calls: 1
			},
			{
				name: "distinct",
				body: "var first=[];var second=[];take(wrap(first));var ints:Array<Int>=second;",
				accepted: true,
				element: "dynamic",
				calls: 1
			},
			{
				name: "conflict",
				body: "var items=[];take(wrap(items));var ints:Array<Int>=items;var strings:Array<String>=items;",
				accepted: false,
				element: "",
				calls: 0
			}
		]) {
			final source = 'class Box<T>{public function new(value:T){}}class Main{'
				+ 'static function wrap<T>(value:T):Box<T>{return new Box(value);}'
				+ 'static function take(value:Box<Dynamic>):Void{}'
				+ 'static function takeNested(value:Box<Array<Dynamic>>):Void{}'
				+ 'static function main():Void{'
				+ entry.body
				+ '}}';
			final root = ".tmp/generic-dynamic-inference-" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			sys.io.File.saveContent(path, source);
			final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
			final process = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if ((code == 0) != entry.accepted || (!entry.accepted && stderr.indexOf("should be") < 0))
				throw "upstream generic inference differs: " + entry.name + stdout + stderr;
			Sys.println("GENERIC_DYNAMIC_INFERENCE_UPSTREAM:PASS " + entry.name);
			var typed:Null<TypedModule> = null;
			try {
				typed = typeSource(source, root, path);
				typed.getBackendProjection();
			} catch (error:haxe.Exception) {
				if (entry.accepted)
					throw error;
				if (error.message.indexOf("conflict") < 0 && error.message.indexOf("not compatible") < 0)
					throw "generic inference rejected for an unrelated reason: " + error.message;
				typed = null;
			}
			if ((typed != null) != entry.accepted)
				throw "local generic inference differs: " + entry.name;
			if (typed != null) {
				var calls = 0;
				function expression(value:TypedExpr):Void {
					final declaration = value.getDeclaration();
					if (value.getTag() == Call
						&& declaration != null
						&& ["take", "takeNested"].contains(declaration.getSignature().getName())) {
						final actual = value.getExpressions()[1].getType();
						if (actual.getSemanticKey() != "nominal:Main.Box<nominal:Array<" + entry.element + ">>")
							throw "generic destination lost inferred shape: " + actual.getSemanticKey();
						value.assertArgumentBinding();
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
				for (owner in typed.getTypedClasses())
					for (fn in owner.getFunctions())
						for (body in fn.getBody().getStatements())
							statement(body);
				if (calls != entry.calls)
					throw "generic destination omitted its observed call";
			}
			Sys.println("GENERIC_DYNAMIC_INFERENCE:PASS " + entry.name);
		}
		runtime();
	}

	/** A nested Dynamic destination keeps the stored array and observes later writes through its concrete alias. */
	static function runtime():Void {
		final root = ".tmp/generic-dynamic-inference-runtime";
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final source = 'class Box<T>{public var value:T;public function new(value:T){this.value=value;}}'
			+ 'class Main{static function wrap<T>(value:T):Box<T>{return new Box(value);}'
			+ 'static function read(value:Box<Dynamic>):Dynamic{return value.value;}'
			+ 'static function count(value:Box<Array<Dynamic>>):Int{return value.value.length;}'
			+ 'static function main():Void{var items=[];var boxed=wrap(items);var erased=read(boxed);'
			+ 'var ints:Array<Int>=items;ints.push(7);trace(erased==items);trace(count(boxed));trace(ints[0]);trace(count(wrap([])));}}';
		sys.io.File.saveContent(path, source);
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		final process = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		final expected = "true\n1\n7\n0\n";
		final upstreamExpected = [for (line in ["true", "1", "7", "0"]) path + ":1: " + line + "\n"].join("");
		if (code != 0 || stdout != upstreamExpected || stderr.length != 0)
			throw "upstream nested generic runtime differs: " + stdout + stderr;
		final typed = typeSource(source, root, path);
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		Sys.println("GENERIC_DYNAMIC_INFERENCE_RUNTIME:PASS");
	}

	/** Resolve Array and its members from the real target library before typing each independently authored source. */
	static function typeSource(source:String, root:String, path:String):TypedModule {
		final args = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "js"
		});
		final defines = Stage3SetupSupport.buildDefinesMap([], "js", "js-native");
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader(paths, defines, index, null, false);
		loader.markResolvedAlready([module]);
		return TyperStage.typeResolvedModule(module, index, loader, true);
	}
}
