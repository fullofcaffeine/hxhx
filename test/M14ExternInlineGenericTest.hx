/** A generic inline body must instantiate its own binders and the call facts inside that body together. */
class M14ExternInlineGenericTest {
	public static function run():Void {
		assertSelectedDynamic();
		final source = '@:native("console") extern class Console {public static function log(value:String):Void;}
enum Flag { On; Off; }
extern class Helper {
public static inline function relay<T>(value:T):T{var local:T=value;return Provider.first(local);}
public static inline function invoke<T>(value:T,callback:T->T):T{return callback(value);}
public static inline function unchecked<T>(value:T):T{return cast value;}
public static inline function choose<T>(flag:Flag,yes:T,no:T):T return switch flag {case On:yes;case Off:no;};
}
class Provider {
public static function first<T>(value:T):T{return value;}
}
class Main {static function main():Void {Console.log(""+Helper.relay(7));Console.log(Helper.relay("kept"));
Console.log(""+Helper.invoke(3,function(value:Int):Int{return value+2;}));
Console.log(Helper.unchecked("unchecked"));
Console.log(Helper.choose(Flag.On,"chosen","wrong"));Console.log(Helper.choose(Flag.Off,"wrong","fallback"));
var opaque:Dynamic="opaque";var result:Dynamic=Helper.relay(opaque);Console.log(result);}}';
		final expected = "7\nkept\n5\nunchecked\nchosen\nfallback\nopaque\n";
		final root = ".tmp/extern-inline-generic";
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		final upstream = @:privateAccess M14JsPlainExternBindingTest.run(compiler == null ? "node_modules/.bin/haxe" : compiler,
			["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
		if (upstream.code != 0)
			throw "upstream generic inline compilation failed: " + upstream.stderr;
		final observed = @:privateAccess M14JsPlainExternBindingTest.run("node", [root + "/upstream.js"]);
		if (observed.code != 0 || observed.stdout != expected)
			throw "upstream generic inline execution differs: " + observed.stdout + observed.stderr;
		Sys.println("EXTERN_INLINE_GENERIC_UPSTREAM:PASS");
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		assertCallProofs(typed);
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		Sys.println("EXTERN_INLINE_GENERIC:PASS");
	}

	/** Selection can settle a binder as Dynamic even though raw Dynamic input cannot infer that binder. */
	static function assertSelectedDynamic():Void {
		final parsed = ParserStage.parse("class Main { static function identity<T>(value:T):T return value; }", "Main.hx");
		final index = TyperIndex.build([new ResolvedModule("Main", "Main.hx", parsed)]);
		final owner = index.getByFullName("Main");
		final signature = owner.staticMethod("identity");
		final declaration = owner.declarationForSignature(signature);
		final dynamicType = TyType.fromHintText("Dynamic");
		final key = declaration.getTypeParameterIds()[0].getCanonicalKey();
		final inferred = @:privateAccess TyMethodGenericBinding.bindings(signature, [dynamicType], 1, declaration.getTypeParameterIds(), index);
		if (inferred == null || inferred.exists(key))
			throw "raw Dynamic input supplied generic inference evidence";
		final selected = @:privateAccess TyMethodGenericBinding.inlineBindings(declaration, [dynamicType], dynamicType, index);
		if (!selected.exists(key) || !selected.get(key).isDynamic())
			throw "selected Dynamic signature lost its generic binder";
		var rejected = false;
		try {
			@:privateAccess TyMethodGenericBinding.inlineBindings(declaration, [dynamicType], TyType.fromHintText("Int"), index);
		} catch (message:String) {
			if (message != "inline specialization has conflicting result evidence")
				throw message;
			rejected = true;
		}
		if (!rejected)
			throw "conflicting selected Dynamic and Int evidence was accepted";
	}

	/** Specialization preserves strict rejection of a later rewrite that changes an operand or its result type. */
	static function assertCallProofs(module:TypedModule):Void {
		final calls = new Array<TypedExpr>();
		var uncheckedCasts = 0;
		function expression(value:TypedExpr):Void {
			if (value.getTag() == Cast && value.getTexts()[0] == "")
				uncheckedCasts++;
			final declaration = value.getDeclaration();
			if (value.getTag() == Call && declaration != null && declaration.getSignature().getName() == "first")
				calls.push(value);
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
			if (HxClassDecl.getName(owner.getSourceDeclaration()) == "Main")
				for (fn in owner.getFunctions())
					for (value in fn.getBody().getStatements())
						statement(value);
		if (calls.length != 3 || Lambda.exists(calls, call -> call.getNamedArguments() == null))
			throw "generic inline expansion lost its selected nested calls";
		if (uncheckedCasts != 1)
			throw "generic inline expansion changed an unchecked cast into a checked cast";
		final operands = calls[0].getExpressions();
		operands[1] = TypedExpr.stringLiteral("wrong", TyType.fromHintText("String"), null);
		@:privateAccess M14NamedCallBindingTest.rejects(() -> calls[0].withExpressions(operands), "stale operand type");
		@:privateAccess M14NamedCallBindingTest.rejects(() -> calls[0].withType(TyType.fromHintText("Bool")), "stale result type");
	}

	static function main():Void
		run();
}
