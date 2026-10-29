import backend.js.JsFunctionScope;
import backend.js.JsStmtEmitter;
import backend.js.JsWriter;

/** Local annotations retain the declaring function's exact generic parameter identities. */
class M14GenericLocalTypeScopeIntegrationTest {
	static function main():Void {
		final source = "class Main { static function run<T>(f:Box<T>->Int, value:Box<T>):Int { var local:Box<T> = value; return f(local); } static function other<T>(value:T):T { var local:T = value; return local; } }";
		final main = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final box = new ResolvedModule("Box", "Box.hx", ParserStage.parse("class Box<T> {}", "Box.hx"));
		final typed = TyperStage.typeResolvedModule(main, TyperIndex.build([main, box]));
		final functions = typed.getTypedClasses()[0].getFunctions();
		final environment = functions[0].getEnvironment();
		final expected = environment.getParams()[1].getType();
		final local = environment.getLocals()[0].getType();
		if (expected.getSemanticKey() != local.getSemanticKey() || !local.getTypeArguments()[0].isTypeParameter())
			throw "local annotation lost the method's generic binder";
		final other = functions[1].getEnvironment();
		if (other.getParams()[0].getType().getSemanticKey() != other.getLocals()[0].getType().getSemanticKey())
			throw "second method lost its generic binder";
		if (other.getLocals()[0].getType().getSemanticKey() == local.getTypeArguments()[0].getSemanticKey())
			throw "same-spelled type parameters from different methods were conflated";
		final holder = new ResolvedModule("Holder", "Holder.hx",
			ParserStage.parse("class Holder<T> { function run(f:T->Int, value:T):Int { var local:T = value; return f(local); } }", "Holder.hx"));
		final holderFunction = TyperStage.typeResolvedModule(holder, TyperIndex.build([holder])).getTypedClasses()[0].getFunctions()[0];
		final holderEnvironment = holderFunction.getEnvironment();
		if (!holderEnvironment.getLocals()[0].getType().isTypeParameter()
			|| holderEnvironment.getLocals()[0].getType().getSemanticKey() != holderEnvironment.getParams()[1].getType().getSemanticKey())
			throw "instance local annotation lost its class generic binder";
		final copiedParameters = environment.getTypeParameters();
		copiedParameters.resize(0);
		if (environment.getTypeParameters().length != 1
			|| environment.copyForInference().getTypeParameters()[0].getCanonicalKey() != environment.getTypeParameters()[0].getCanonicalKey()
			|| environment.createBodyReplay().getTypeParameters()[0].getCanonicalKey() != environment.getTypeParameters()[0].getCanonicalKey())
			throw "generic context was mutable or lost during environment copying";
		final projection = TypedBodySource.functionProjection(functions[0]);
		final writer = new JsWriter();
		final scope = new JsFunctionScope(new haxe.ds.StringMap<String>(), null, null, projection.getLocalCatalog());
		JsStmtEmitter.emitFunctionBody(writer, projection.getBody(), scope);
		final process = new sys.io.Process("node", [
			"-e",
			"function run(f,value){" + writer.toString() + "}\nconsole.log(run(x=>x.value+1,{value:7}));"
		]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != "8\n")
			throw "generic local callback execution differs: " + output + errors;
		Sys.println("GENERIC_LOCAL_TYPE_SCOPE:PASS");
	}
}
