/** Written storage types survive inference even when an initializer requires a target conversion. */
class M14DeclaredLocalTransferTypeTest {
	static function main():Void {
		final source = 'class Main { static function source(value:Null<Int>):Null<Int> return value; static function probe(value:Null<Int>):Void { var local:Int = source(value); local = source(value); final inferred = source(value); final wide:Null<Int> = 1; } }';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final probe = typed.getTypedClasses()[0].getFunctions().filter(fn -> fn.getDeclaration().getSignature().getName() == "probe")[0];
		final locals = probe.getEnvironment().getLocals();
		final expected = ["primitive:Int", "nullable:primitive:Int", "nullable:primitive:Int"];
		if (locals.length != expected.length)
			throw "declared local fixture lost bindings";
		for (index in 0...locals.length)
			if (locals[index].getType().getSemanticKey() != expected[index])
				throw "written local type changed at " + index + ": " + locals[index].getType().getSemanticKey();
		TypedBodySource.functionProjection(probe);
		Sys.println("DECLARED_LOCAL_TRANSFER_TYPES:PASS");
	}
}
