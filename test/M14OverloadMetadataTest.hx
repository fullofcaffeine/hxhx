/** Authored overload metadata must publish real, distinct signatures before call selection. */
class M14OverloadMetadataTest {
	static function check(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function main():Void {
		final source = 'extern class Api<T> {'
			+ '@:overload(function(value:String, ?offset:Int):String {}) public function select(value:T):T;'
			+ '@:overload(function<T>(value:T):T {}) public static function echo(value:Int):Int; }';
		final parsed = ParserStage.parse(source, "Api.hx");
		final index = TyperIndex.build([new ResolvedModule("Api", "Api.hx", parsed)]);
		final owner = index.getByFullName("Api");
		final choices = owner.instanceMethodCandidates("select");
		check(choices.length == 2, "overload metadata did not add its callable signature");
		check(choices[0].getArgs()[0].isTypeParameter(), "overload replaced the primary class parameter");
		check(choices[1].getArgs()[0].getSemanticKey() == "primitive:String"
			&& choices[1].getArgOptional()[1]
			&& choices[1].getReturnType().getSemanticKey() == "primitive:String",
			"overload lost its argument/result/optional facts");
		check(owner.declarationForSignature(choices[0])
			.getIdentity()
			.getCanonicalKey() != owner.declarationForSignature(choices[1])
			.getIdentity()
			.getCanonicalKey(),
			"overload and primary share a declaration identity");
		final echo = owner.staticMethodCandidates("echo");
		check(echo.length == 2, "generic overload was not published");
		final generic = owner.declarationForSignature(echo[1]);
		check(generic.getTypeParameterIds().length == 1
			&& echo[1].getArgs()[0].getTypeParameterIdentity().equals(generic.getTypeParameterIds()[0])
			&& echo[1].getReturnType().getTypeParameterIdentity().equals(generic.getTypeParameterIds()[0]),
			"overload generic binder lost its own scope");
		check(HxClassDecl.getFunctions(HxModuleDecl.getClasses(parsed.getDecl())[0]).length == 2, "metadata signatures became extra source implementations");
		check(!generic.getHasBody(), "empty overload metadata acquired an executable body");
		final root = ".tmp/overload_signature_dependencies";
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + "/Receiver.hx",
			'extern class Receiver {' + '@:overload(function(value:Payload):Payload {}) public function select(value:Int):Int; }');
		sys.io.File.saveContent(root + "/Payload.hx", 'class Payload {}');
		final roots = ResolverStage.parseProjectRootsShallow([root], ["Receiver"]);
		final lazyIndex = TyperIndex.buildHeaders(roots);
		final loader = new ModuleLoader([root], new haxe.ds.StringMap<String>(), lazyIndex, null, false);
		loader.markResolvedAlready(roots);
		final alternatives = lazyIndex.getByFullName("Receiver").instanceMethodCandidates("select");
		check(alternatives.length == 2
			&& alternatives[1].getArgs()[0].getSemanticKey() == "nominal:Payload"
			&& alternatives[1].getReturnType().getSemanticKey() == "nominal:Payload",
			"signature-only overload dependency was not loaded before publication");
		check(loader.drainNewModules().length == 1, "overload dependency must be loaded exactly once");
		for (metadata in [
			'@:overload(function(value:String):String {return "bad";})',
			'@:overload(function(value:String) {})',
			'@:overload(function(value):String {})'
		]) {
			var rejected = false;
			try {
				final text = 'extern class Broken {' + metadata + ' public function select(value:Int):Int;}';
				TyperIndex.build([new ResolvedModule("Broken", "Broken.hx", ParserStage.parse(text, "Broken.hx"))]);
			} catch (error:TyperError) {
				rejected = error.filePath == "Broken.hx";
			}
			check(rejected, "invalid overload did not retain its declaring-file diagnostic");
		}
		var implementedRejected = false;
		try {
			final text = 'class Implemented {@:overload(function(value:String):String {}) public static function choose(value:Int):Int {return value;}}';
			TyperIndex.build([
				new ResolvedModule("Implemented", "Implemented.hx", ParserStage.parse(text, "Implemented.hx"))
			]);
		} catch (error:TyperError) {
			implementedRejected = error.message.indexOf("implementation routing") >= 0;
		}
		check(implementedRejected, "implemented overload must not silently become a bodyless extern");
		Sys.println("OVERLOAD_METADATA:PASS");
	}
}
