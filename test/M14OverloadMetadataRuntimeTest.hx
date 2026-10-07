import backend.BackendContext;
import backend.js.JsBackend;

/** Calls selected from metadata must reach the real JavaScript host with unchanged values. */
class M14OverloadMetadataRuntimeTest {
	static function run(command:String, arguments:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function check(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function main():Void {
		final root = ".tmp/overload_metadata_runtime";
		sys.FileSystem.createDirectory(root);
		final declarations = '@:native("String") extern class Host {'
			+ '@:overload(function(code:String):String {}) public static function fromCharCode(code:Int):String; }'
			+ '@:native("console") extern class Console {public static function log(value:String):Void;}';
		final source = declarations
			+ 'class Main {static function main():Void {'
			+ 'Console.log(Host.fromCharCode("65")); Console.log(Host.fromCharCode(66));}}';
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		final expected = "A\nB\n";
		final upstream = run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
		check(upstream.code == 0, "upstream rejected the overload runtime fixture: " + upstream.stderr);
		final reference = run("node", [root + "/upstream.js"]);
		check(reference.code == 0 && reference.stdout == expected, "upstream host result differs: " + reference.stderr);
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final output = root + "/native.js";
		new JsBackend().emit(new MacroExpandedProgram([typed], false),
			new BackendContext(root, output, "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
		final native = run("node", [output]);
		check(native.code == 0 && native.stdout == expected, "native metadata overload call differs: " + native.stderr);
		final invalid = declarations + 'class Main {static function main():Void {Host.fromCharCode(true);}}';
		sys.io.File.saveContent(path, invalid);
		check(run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/invalid.js"]).code != 0,
			"upstream accepted the unlisted Boolean overload");
		var rejected = false;
		try {
			final broken = new ResolvedModule("Main", path, ParserStage.parse(invalid, path));
			TyperStage.typeResolvedModule(broken, TyperIndex.build([broken]));
		} catch (error:TyperError) {
			rejected = true;
		}
		check(rejected, "an unlisted argument type silently acquired an overload");
		Sys.println("OVERLOAD_METADATA_RUNTIME:PASS");
		selectionOrder();
		omittedRuntime();
	}

	/** Primary and metadata order decide a group even when a later signature is more specific. */
	static function selectionOrder():Void {
		for (entry in [
			{
				name: "primary_int",
				metadata: '@:overload(function(name:String,?options:String):String{})',
				parameters: 'name:String,?options:{kind:String}',
				result: "Int",
				call: '"word"',
				expected: "Int"
			},
			{
				name: "primary_string",
				metadata: '@:overload(function(name:String,?options:String):Int{})',
				parameters: 'name:String,?options:{kind:String}',
				result: "String",
				call: '"word"',
				expected: "String"
			},
			{
				name: "explicit_null",
				metadata: '@:overload(function(name:String,?options:String):Int{})',
				parameters: 'name:String,?options:{kind:String}',
				result: "String",
				call: '"word",null',
				expected: "String"
			},
			{
				name: "metadata_string_first",
				metadata: '@:overload(function(name:String,?options:String):String{})@:overload(function(name:String,?options:Int):Int{})',
				parameters: 'name:String,options:Bool',
				result: "Bool",
				call: '"word"',
				expected: "String"
			},
			{
				name: "metadata_int_first",
				metadata: '@:overload(function(name:String,?options:Int):Int{})@:overload(function(name:String,?options:String):String{})',
				parameters: 'name:String,options:Bool',
				result: "Bool",
				call: '"word"',
				expected: "Int"
			},
			{
				name: "dynamic_primary",
				metadata: '@:overload(function(value:Int):Int{})',
				parameters: 'value:Dynamic',
				result: "String",
				call: '7',
				expected: "String"
			},
			{
				name: "float_primary",
				metadata: '@:overload(function(value:Int):Int{})',
				parameters: 'value:Float',
				result: "String",
				call: '7',
				expected: "String"
			},
			{
				name: "metadata_specificity",
				metadata: '@:overload(function(value:Dynamic):String{})@:overload(function(value:Int):Int{})',
				parameters: 'value:Bool',
				result: "Bool",
				call: '7',
				expected: "String"
			}
		]) {
			final root = ".tmp/metadata_order_" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			final source = 'extern class Api{'
				+ entry.metadata
				+ 'public static function choose('
				+ entry.parameters
				+ '):'
				+ entry.result
				+ ';}class Main{static function main():Void{var selected=Api.choose('
				+ entry.call
				+ ');var expected:'
				+ entry.expected
				+ '=selected;}}';
			sys.io.File.saveContent(path, source);
			final reference = run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
			check(reference.code == 0, "upstream overload order differs: " + entry.name + reference.stderr);
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			var calls = 0;
			function inspect(expression:TypedExpr):Void {
				final declaration = expression.getDeclaration();
				if (expression.getTag() == Call && declaration != null && declaration.getSignature().getName() == "choose") {
					calls++;
					check(expression.getNamedArguments() != null, "ordered call lost its argument binding");
					check(declaration.getSignature().getReturnType().getSemanticKey() == "primitive:" + entry.expected
						&& expression.getType().getSemanticKey() == "primitive:" + entry.expected,
						"wrong declaration selected: "
						+ entry.name);
				}
				for (child in expression.getExpressions())
					inspect(child);
			}
			for (owner in typed.getTypedClasses())
				for (method in owner.getFunctions())
					for (statement in method.getBody().getStatements())
						for (expression in statement.getExpressions())
							inspect(expression);
			check(calls == 1, "ordered overload case missed its call");
			typed.getBackendProjection();
			Sys.println("METADATA_OVERLOAD_ORDER:PASS " + entry.name);
		}
	}

	/** Omitted arguments remain absent at the real host boundary; supplied alternatives keep their values. */
	static function omittedRuntime():Void {
		final root = ".tmp/metadata_order_runtime";
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final source = '@:native("Host")extern class Api{@:overload(function(name:String,?options:String):String{})'
			+ 'public static function choose(name:String,?options:{kind:String}):String;}'
			+ '@:native("console")extern class Console{public static function log(value:String):Void;}'
			+ 'class Main{static function main():Void{Console.log(Api.choose("first"));Console.log(Api.choose("second","tag"));'
			+ 'Console.log(Api.choose("third",{kind:"record"}));}}';
		sys.io.File.saveContent(path, source);
		final harness = root + "/host.cjs";
		sys.io.File.saveContent(harness,
			'let calls=0;global.Host={choose(name,options){calls++;'
			+ 'if(name==="second"&&options!=="tag")throw Error("text option");'
			+ 'if(name==="third"&&options.kind!=="record")throw Error("record option");'
			+ 'return name+":"+arguments.length;}};require(process.argv[2]);if(calls!==3)throw Error("call count");');
		final reference = run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
		check(reference.code == 0, reference.stderr);
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		new JsBackend().emit(new MacroExpandedProgram([typed], false),
			new BackendContext(root, root + "/native.js", "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
		for (file in ["upstream.js", "native.js"]) {
			final result = run("node", [harness, sys.FileSystem.fullPath(root + "/" + file)]);
			check(result.code == 0 && result.stdout == "first:1\nsecond:2\nthird:2\n",
				"overload host arguments differ: "
				+ file
				+ result.stdout
				+ result.stderr);
		}
		Sys.println("METADATA_OVERLOAD_OMISSION_RUNTIME:PASS");
	}
}
