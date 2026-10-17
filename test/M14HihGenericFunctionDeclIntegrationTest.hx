import backend.js.JsFunctionScope;
import backend.js.JsStmtEmitter;
import backend.js.JsWriter;

/** Method generic signatures preserve names and nested constraints across both parser entry points. */
class M14HihGenericFunctionDeclIntegrationTest {
	static function fail(msg:String):Void {
		throw msg;
	}

	static function assertTrue(ok:Bool, label:String):Void {
		if (!ok)
			fail(label);
	}

	static function assertEqString(actual:String, expected:String, label:String):Void {
		if (actual != expected)
			fail(label + ": expected " + expected + ", got " + actual);
	}

	static function assertEqInt(actual:Int, expected:Int, label:String):Void {
		if (actual != expected)
			fail(label + ": expected " + expected + ", got " + actual);
	}

	static function findClass(decl:HxModuleDecl, name:String):HxClassDecl {
		for (cls in HxModuleDecl.getClasses(decl)) {
			if (HxClassDecl.getName(cls) == name)
				return cls;
		}
		fail("missing class " + name);
		return null;
	}

	static function findFunction(cls:HxClassDecl, name:String):HxFunctionDecl {
		for (fn in HxClassDecl.getFunctions(cls)) {
			if (HxFunctionDecl.getName(fn) == name)
				return fn;
		}
		fail("missing function " + HxClassDecl.getName(cls) + "." + name);
		return null;
	}

	static function assertArg(fn:HxFunctionDecl, index:Int, name:String, typeHint:String):Void {
		final args = HxFunctionDecl.getArgs(fn);
		assertTrue(index >= 0 && index < args.length, HxFunctionDecl.getName(fn) + ": missing arg " + index);
		final arg = args[index];
		assertEqString(HxFunctionArg.getName(arg), name, HxFunctionDecl.getName(fn) + ": arg name " + index);
		assertEqString(HxFunctionArg.getTypeHint(arg), typeHint, HxFunctionDecl.getName(fn) + ": arg type " + index);
	}

	static function assertMetadataContains(fn:HxFunctionDecl, value:String, label:String):Void {
		for (meta in HxFunctionDecl.getMetadata(fn))
			if (meta == value)
				return;
		fail(label + ": missing metadata " + value + ", got " + Std.string(HxFunctionDecl.getMetadata(fn)));
	}

	static function main() {
		final src = '@:generic class GenericMethods<T> {\n'
			+ '  public function new() {}\n'
			+ '  public function map<X>(f:T->X):Array<X> { return []; }\n'
			+ '  public static function create<T>():GenericMethods<T> { return new GenericMethods<T>(); }\n'
			+ '  public function fold<A>(init:A, f:A->T->A):A { return init; }\n'
			+ '}\n'
			+ 'class Main {\n'
			+ '  static function main() {}\n'
			+ '}\n';

		final decl = new HxParser(src).parseModule("Main");
		final cls = findClass(decl, "GenericMethods");

		final map = findFunction(cls, "map");
		assertEqString(HxFunctionDecl.getName(map), "map", "method type parameters must not become part of the function name");
		assertTrue(!HxFunctionDecl.getIsStatic(map), "map should remain an instance method");
		assertEqInt(HxFunctionDecl.getArgs(map).length, 1, "map arg count");
		assertArg(map, 0, "f", "T->X");
		assertEqString(HxFunctionDecl.getReturnTypeHint(map), "Array<X>", "map return type");

		final create = findFunction(cls, "create");
		assertTrue(HxFunctionDecl.getIsStatic(create), "create should remain static");
		assertEqInt(HxFunctionDecl.getArgs(create).length, 0, "create arg count");
		assertEqString(HxFunctionDecl.getReturnTypeHint(create), "GenericMethods<T>", "create return type");

		final fold = findFunction(cls, "fold");
		assertEqInt(HxFunctionDecl.getArgs(fold).length, 2, "fold arg count");
		assertArg(fold, 0, "init", "A");
		assertArg(fold, 1, "f", "A->T->A");
		assertEqString(HxFunctionDecl.getReturnTypeHint(fold), "A", "fold return type");

		final srcWithNestedComma = 'class PairMapChecks {\n' + '  function compare<K, V>(left:Map<K, V>, right:Map<K, V>, ?pos:haxe.PosInfos) {}\n' + '}\n';
		final nestedDecl = new HxParser(srcWithNestedComma).parseModule("PairMapChecks");
		final compare = findFunction(findClass(nestedDecl, "PairMapChecks"), "compare");
		assertEqInt(HxFunctionDecl.getArgs(compare).length, 3, "nested generic comma arg count");
		assertArg(compare, 0, "left", "Map<K,V>");
		assertArg(compare, 1, "right", "Map<K,V>");
		assertArg(compare, 2, "pos", "haxe.PosInfos");

		final constrainedSrc = 'class GenericReflection {\n'
			+ '  @:generic static function gf3 < A:haxe.Constraints.Constructible<String -> Void>, B:Array<A> > (a:A, b:B) {\n'
			+ '    var clone = new A("foo");\n'
			+ '    b.push(clone);\n'
			+ '    return b;\n'
			+ '  }\n'
			+ '}\n';
		final constrainedDecl = new HxParser(constrainedSrc).parseModule("GenericReflection");
		final gf3 = findFunction(findClass(constrainedDecl, "GenericReflection"), "gf3");
		assertEqInt(HxFunctionDecl.getArgs(gf3).length, 2, "constrained gf3 arg count");
		assertArg(gf3, 0, "a", "A");
		assertArg(gf3, 1, "b", "B");
		assertMetadataContains(gf3, "__hxhx_fn_type_params=A,B", "constrained gf3 type params");
		checkCommentsAndMalformedConstraints();
		checkTypedGenericExecution();
	}

	/** Commas inside comments cannot manufacture generic declarations. */
	static function checkCommentsAndMalformedConstraints():Void {
		final source = "class Main { static function first<T /*, Phantom*/:Array<Int>>(value:T):Int { return value[0]; } }";
		final method = findFunction(findClass(new HxParser(source).parseModule("Main"), "Main"), "first");
		final scanned = ParserStageScanHelpers.scanClassBodyForStatics(source, source.indexOf("{") + 1).functions[0];
		for (declaration in [method, scanned]) {
			assertMetadataContains(declaration, "__hxhx_fn_type_params=T", "comment cannot create a generic binder");
			assertMetadataContains(declaration, "__hxhx_fn_type_constraint=T:Array<Int>", "constraint belongs to the actual binder");
		}
		final intersection = HxFunctionSyntaxParser.parse("function pair<T:{x:Int} & {y:Int}>(value:T):Int { return value.x + value.y; }").typeParameters;
		assertEqInt(intersection.length, 1, "intersection binder count");
		assertEqInt(intersection[0].constraints.length, 2, "intersection constraints stay separate");
		assertEqString(HxFunctionTypeParamMetadata.constraints(HxFunctionTypeParamMetadata.fromGenericText("<T:{x:Int} & {y:Int}>")).get("T"),
			"{x:Int}&{y:Int}", "intersection projection keeps both constraints");
		for (parameters in ["<T:>", "<T,,U>"]) {
			var rejected = false;
			try
				new HxParser("class Invalid { static function reject" + parameters + "() {} }").parseModule("Invalid")
			catch (_:HxParseError)
				rejected = true;
			assertTrue(rejected, "malformed generic declaration must fail: " + parameters);
		}
	}

	/** The ordinary typer and JavaScript body emitter must consume the one real binder. */
	static function checkTypedGenericExecution():Void {
		final source = "class Main { static function echo<T /*, Phantom*/>(value:T):T { return value; } "
			+ "static function run():Int { return Main.echo(7); } }";
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final index = TyperIndex.build([module]);
		final owner = index.getByFullName("Main");
		final declaration = owner.declarationForSignature(owner.staticMethod("echo"));
		assertEqInt(declaration.getTypeParameterIds().length, 1, "typing must allocate only the authored binder");
		final names = new haxe.ds.StringMap<String>();
		names.set("Main", "Main");
		final methods = new Array<String>();
		for (fn in TyperStage.typeResolvedModule(module, index).getTypedClasses()[0].getFunctions()) {
			final projection = TypedBodySource.functionProjection(fn);
			final writer = new JsWriter();
			JsStmtEmitter.emitFunctionBody(writer, projection.getBody(), new JsFunctionScope(names, null, null, projection.getLocalCatalog()));
			final parameters = [for (parameter in fn.getEnvironment().getParams()) parameter.getName()];
			methods.push(fn.getEnvironment().getName() + ":function(" + parameters.join(",") + "){" + writer.toString() + "}");
		}
		final process = new sys.io.Process("node", ["-e", "const Main={" + methods.join(",") + "};console.log(Main.run());"]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		assertTrue(code == 0 && output == "7\n", "generic method execution differs: " + output + errors);
	}
}
