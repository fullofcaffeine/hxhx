/** Compare a declared abstract conversion upstream and through shared constructor publication. */
class M14ConstructorAbstractArgumentTest {
	/** An invalid or undeclared conversion must not acquire a checked argument binding. */
	static function reject(signature:TyCallableSignature, expression:HxExpr, type:TyType, index:TyperIndex):Void {
		try
			TyCallbackArgumentContext.publish(signature, [expression], [type], index)
		catch (failure:haxe.Exception) {
			if (failure.message.indexOf("cannot publish captured callback arguments:") != 0)
				throw failure;
			return;
		}
		throw "undeclared abstract conversion acquired a checked binding";
	}

	static function main():Void {
		final root = "test/oracle/constructor_abstract_argument_seed";
		final overrideCompiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		final compiler = overrideCompiler == null ? "node_modules/.bin/haxe" : overrideCompiler;
		final child = new sys.io.Process(compiler, ["-cp", root, "-main", "Main", "--interp"]);
		final output = child.stdout.readAll().toString();
		final errors = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0 || errors != "" || output != "hello\n")
			throw "upstream abstract constructor contract differs: " + output + errors;
		final path = root + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final index = TyperIndex.build([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index);
		JsRuntimeFixture.assertRuntime(typed, "Main", "hello\n");
		final box = index.getByFullName("Main.Box");
		final signature = TyCallableSignature.fromDeclaration(box.declarationForSignature(box.instanceMethodCandidates("new")[0]));
		reject(signature, HxExpr.EInt(3), TyType.fromHintText("Int"), index);
		final opaque = new ResolvedModule("Opaque", "Opaque.hx",
			ParserStage.parse('abstract Opaque(String) {} class Holder { public function new(value:Opaque) {} }', "Opaque.hx"));
		final opaqueIndex = TyperIndex.build([opaque]);
		final holder = opaqueIndex.getByFullName("Opaque.Holder");
		reject(TyCallableSignature.fromDeclaration(holder.declarationForSignature(holder.instanceMethodCandidates("new")[0])), HxExpr.EString("hello"),
			TyType.fromHintText("String"), opaqueIndex);
		Sys.println("CONSTRUCTOR_ABSTRACT_ARGUMENT:PASS");
	}
}
