/** Constructor inference and publication preserve authored metadata-overload order. */
class M14ConstructorOverloadMetadataTest {
	static function main():Void {
		M14GenericConstructorOverloadTest.checkConstructor();
		primaryOrder();
	}

	/** The applicable primary Float input must not let a later generic alternative bind the owner to Int. */
	static function primaryOrder():Void {
		final root = ".tmp/constructor_metadata_order";
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final source = '@:native("NativeHost")extern class Native<T>{@:overload(function(value:T):Void{})public function new(value:Float);public var label:String;}'
			+ '@:native("console")extern class Console{public static function log(value:String):Void;}'
			+ 'class Main{static function main():Void{var item:Native<String>=new Native(7);Console.log(item.label);}}';
		sys.io.File.saveContent(path, source);
		observe("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"], "");
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		var allocations = 0;
		function inspect(expression:TypedExpr):Void {
			if (expression.getTag() == NewValue) {
				allocations++;
				final application = expression.getConstructorApplication();
				if (application == null
					|| application.getDeclaration().getImplementation() != application.getDeclaration()
					|| application.getParameterTypes()[0].getSemanticKey() != "primitive:Float"
					|| expression.getType().getTypeArguments()[0].getSemanticKey() != "primitive:String")
					throw "constructor metadata order changed its declaration or owner argument";
			}
			for (child in expression.getExpressions())
				inspect(child);
		}
		for (owner in typed.getTypedClasses())
			for (method in owner.getFunctions())
				for (statement in method.getBody().getStatements())
					for (expression in statement.getExpressions())
						inspect(expression);
		if (allocations != 1)
			throw "constructor order fixture missed its allocation";
		final harness = root + "/host.cjs";
		sys.io.File.saveContent(harness,
			'let calls=0;global.NativeHost=class{constructor(value){calls++;' +
			'if(arguments.length!==1||value!==7)throw Error("constructor arguments");this.label="made";}};' +
			'require(process.argv[2]);if(calls!==1)throw Error("constructor count");');
		new backend.js.JsBackend().emit(new MacroExpandedProgram([typed], false),
			new backend.BackendContext(root, root + "/native.js", "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
		for (file in ["upstream.js", "native.js"])
			observe("node", [harness, sys.FileSystem.fullPath(root + "/" + file)], "made\n");
		Sys.println("CONSTRUCTOR_METADATA_ORDER:PASS");
	}

	/** The host observes argument count, value, and exactly one construction in both generated programs. */
	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected)
			throw "constructor order observer failed: " + command + output + errors;
	}
}
