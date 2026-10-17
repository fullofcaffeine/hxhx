import TyAssignmentCompatibility.TyAssignmentNullPolicy;

/** Nullable structural arguments retain their source type and value at the real host boundary. */
class M14NullableStructuralArgumentTest {
	static function main():Void {
		check();
	}

	public static function check():Void {
		for (entry in [
			{name: "record", declaration: "typedef Options={var ?alpha:Bool;};", target: "{}"},
			{name: "nullable_target", declaration: "typedef Options={var ?alpha:Bool;};", target: "Null<{}>"},
			{name: "class", declaration: "extern class Options{public var alpha:Bool;}", target: "{}"}
		]) {
			final root = ".tmp/nullable_structural_" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			final source = entry.declaration
				+ '@:native("Host")extern class Host{public static function take(value:'
				+ entry.target
				+ '):String;public static function input():Options;public static function record(value:String):Void;}'
				+ 'class Main{static function call(?options:Options):String{return Host.take(options);}'
				+ 'static function main():Void{Host.record(call());Host.record(call(null));Host.record(call(Host.input()));}}';
			sys.io.File.saveContent(path, source);
			final reference = run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
			if (reference.code != 0)
				throw "upstream nullable structural call failed: " + reference.stderr;
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			var calls = 0;
			function inspect(expression:TypedExpr):Void {
				final declaration = expression.getDeclaration();
				if (expression.getTag() == Call && declaration != null && declaration.getSignature().getName() == "take") {
					calls++;
					expression.assertArgumentBinding();
					final children = expression.getExpressions();
					final actual = children[children.length - 1].getType();
					if (!actual.isNullable() || (!actual.unwrapNull().isAnonymous() && actual.unwrapNull().getNominalIdentity() == null))
						throw "structural call erased its nullable source type";
					final expected = declaration.getSignature().getArgs()[0];
					if (!expected.isNullable() && TyAssignmentCompatibility.classify(expected, actual, Strict) != Incompatible)
						throw "unchecked call proof weakened strict null policy";
				}
				for (child in expression.getExpressions())
					inspect(child);
			}
			for (owner in typed.getTypedClasses())
				for (method in owner.getFunctions())
					for (statement in method.getBody().getStatements())
						for (expression in statement.getExpressions())
							inspect(expression);
			if (calls != 1)
				throw "nullable structural fixture missed its selected call";
			final harness = root + "/host.cjs";
			sys.io.File.saveContent(harness,
				'let calls=0,reads=0;const value={alpha:true};global.Host={input(){reads++;return value;},'
				+ 'take(input){calls++;if(arguments.length!==1)throw Error("argument count");if(input==null)return "null";'
				+ 'if(input!==value)throw Error("record identity");return "object";},record(value){console.log(value);}};'
				+ 'require(process.argv[2]);if(calls!==3||reads!==1)throw Error("evaluation count");');
			new backend.js.JsBackend().emit(new MacroExpandedProgram([typed], false),
				new backend.BackendContext(root, root + "/native.js", "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
			for (file in ["upstream.js", "native.js"]) {
				final result = run("node", [harness, sys.FileSystem.fullPath(root + "/" + file)]);
				if (result.code != 0 || result.stdout != "null\nnull\nobject\n")
					throw "nullable structural runtime differs: " + file + result.stdout + result.stderr;
			}
			Sys.println("NULLABLE_STRUCTURAL_ARGUMENT:PASS " + entry.name);
		}
		final root = ".tmp/nullable_structural_wrong";
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final source = 'typedef Options={var value:String;};extern class Host{public static function take(value:{var value:Int;}):Int;}'
			+ 'class Main{static function call(?options:Options):Int{return Host.take(options);}static function main():Void{}}';
		sys.io.File.saveContent(path, source);
		if (run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/invalid.js"]).code == 0)
			throw "upstream accepted incompatible record fields";
		var rejected = false;
		try {
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		} catch (error:TyperError) {
			rejected = error.message.indexOf("No compatible method signature") >= 0;
		}
		if (!rejected)
			throw "nullable structural normalization accepted incompatible fields";
		Sys.println("NULLABLE_STRUCTURAL_ARGUMENT:PASS incompatible");
	}

	/** Compare actual process results, including the independent host assertions. */
	static function run(command:String, arguments:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}
}
