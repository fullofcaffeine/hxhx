import backend.BackendContext;
import backend.js.JsTargetCore;

/** Defaults permit omission through method references without changing the parameter's body type. */
class M14MethodDefaultCallableIntegrationTest {
	static function module(name:String, source:String):ResolvedModule {
		return new ResolvedModule(name, name + ".hx", ParserStage.parse(source, name + ".hx"));
	}

	static function check(ok:Bool, message:String):Void {
		if (!ok)
			throw message;
	}

	static function main():Void {
		final provider = module("Provider",
			"class Provider { public static function choose(value:Int=7):Int return value; "
			+ "public static function other(value:Int=9):Int return value; "
			+ "public static function nullable(value:Null<Int>=null):Bool return value == null; "
			+ "public static function required(value:Null<Int>):Int return value == null ? 0 : value; }");
		final main = module("Main",
			"import Provider.choose as selected; import Provider.other; import Alternate.choose as alternate; class Main { static function main():Void { "
			+ "var f=Provider.choose; var h=other; var n=Provider.nullable; var g=selected; "
			+
			"if (g()!=7 || g(null)!=7 || g(4)!=4 || f()!=7 || f(null)!=7 || f(3)!=3 || h()!=9 || Provider.choose()!=7 || !n() || n(3)) throw 'default mismatch'; "
			+ "var a=alternate; if (a()!=13 || a(6)!=6) throw 'provider mismatch'; "
			+ "{ var selected=Provider.other; if (selected()!=9) throw 'local shadow mismatch'; } } }");
		final alternate = module("Alternate", "class Alternate { public static function choose(value:Int=13):Int return value; }");
		final index = TyperIndex.build([provider, main, alternate]);
		final owner = index.getByFullName("Provider");
		final signature = owner.staticMethod("choose");
		check(signature.acceptsArity(0), "defaulted method rejected omission in its indexed signature");
		check(!owner.staticMethod("required").acceptsArity(0), "nullable type made a required parameter omittable");
		final declaration = owner.declarationForSignature(signature);
		check(!HxFunctionArg.getIsOptional(HxFunctionDecl.getArgs(declaration.getSourceDeclaration())[0]), "typing changed the written optional marker");
		check(signature.getArgs()[0].getSemanticKey() == TyType.fromHintText("Int").getSemanticKey(), "omission changed the body-visible Int type");
		final callable = TyCallableSignature.fromDeclaration(declaration);
		check(callable.getParameters()[0].isOptional, "method reference lost omission permission");
		final typed = [
			TyperStage.typeResolvedModule(provider, index),
			TyperStage.typeResolvedModule(main, index),
			TyperStage.typeResolvedModule(alternate, index)
		];
		for (local in typed[1].getTypedClasses()[0].getFunctions()[0].getEnvironment().getLocals())
			check(local.getType().isFunction() && local.getType().getFunctionParameters()[0].isOptional,
				"qualified method reference lost its concrete optional signature");
		final snapshot = CompilerDependencyCollector.collect(typed, index);
		for (ownerName in ["Provider", "Alternate"]) {
			final exactOwner = index.getByFullName(ownerName);
			final exact = exactOwner.declarationForSignature(exactOwner.staticMethod("choose")).getIdentity().getCanonicalKey();
			var observed = false;
			for (edge in snapshot.getEdges())
				if (edge.consumerModule == "Main" && edge.providerModule == ownerName && edge.factIdentity == "declaration:" + exact)
					observed = true;
			check(observed, "method value lost its exact provider dependency: " + ownerName);
		}
		// Identical bodies and callable types must still distinguish the selected provider.
		function referenceBody(ownerName:String):String {
			final consumer = module("Consumer",
				"import " + ownerName + ".choose as selected; class Consumer { static function run():Void { var f=selected; } }");
			final localIndex = TyperIndex.build([provider, alternate, consumer]);
			final result = TyperStage.typeResolvedModule(consumer, localIndex);
			return CompilerTypedTreeRevision.functionBody(result.getTypedClasses()[0].getFunctions()[0]);
		}
		check(referenceBody("Provider") != referenceBody("Alternate"), "changing the selected provider did not change the typed body revision");
		final output = Sys.getCwd() + "/.tmp/m14_method_default_callable";
		final result = new JsTargetCore().emit(new MacroExpandedProgram(typed, false),
			new BackendContext(output, output + "/main.js", "Main", true, false, new haxe.ds.StringMap<String>()));
		final process = new sys.io.Process("node", [result.entryPath]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		check(code == 0 && stdout == "", "generated defaulted calls failed: " + stdout + stderr);
		final invalid = module("Invalid", "class Invalid { static function run():Int { var f=Provider.required; return f(); } }");
		var rejected = false;
		try
			TyperStage.typeResolvedModule(invalid, TyperIndex.build([provider, invalid]))
		catch (error:TyperError)
			rejected = Std.string(error).indexOf("Not enough arguments") >= 0;
		check(rejected, "required nullable method reference accepted omission");
		Sys.println("METHOD_DEFAULT_CALLABLE:PASS");
	}
}
