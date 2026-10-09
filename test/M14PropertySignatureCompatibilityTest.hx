/** Property signatures use directional assignment; calls retain their actual accessor types. */
class M14PropertySignatureCompatibilityTest {
	public static function check():Void {
		for (entry in [
			{
				name: "getter_dynamic_object",
				field: "Box",
				input: "",
				result: "Dynamic",
				body: "new Box()",
				valid: true
			},
			{
				name: "getter_dynamic",
				field: "Int",
				input: "",
				result: "Dynamic",
				body: "7",
				valid: true
			},
			{
				name: "getter_inferred",
				field: "Int",
				input: "",
				result: "",
				body: "7",
				valid: true
			},
			{
				name: "getter_widen",
				field: "Float",
				input: "",
				result: "Int",
				body: "7",
				valid: true
			},
			{
				name: "getter_nullable",
				field: "Int",
				input: "",
				result: "Null<Int>",
				body: "7",
				valid: true
			},
			{
				name: "getter_narrow",
				field: "Int",
				input: "",
				result: "Float",
				body: "7.5",
				valid: false
			},
			{
				name: "getter_wrong",
				field: "Int",
				input: "",
				result: "String",
				body: '"bad"',
				valid: false
			},
			{
				name: "setter_dynamic",
				field: "Int",
				input: "Dynamic",
				result: "Dynamic",
				body: "7",
				valid: true
			},
			{
				name: "setter_wider_input",
				field: "Int",
				input: "Float",
				result: "Int",
				body: "7",
				valid: true
			},
			{
				name: "setter_narrow_input",
				field: "Float",
				input: "Int",
				result: "Float",
				body: "7",
				valid: false
			},
			{
				name: "setter_wider_result",
				field: "Int",
				input: "Int",
				result: "Float",
				body: "7",
				valid: false
			},
			{
				name: "setter_narrow_result",
				field: "Float",
				input: "Float",
				result: "Int",
				body: "7",
				valid: true
			}
		]) {
			final writing = entry.input != "";
			final root = ".tmp/property_signature_" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			// Dynamic is deliberate source behavior here: upstream accepts it in accessor contracts.
			final source = (entry.field == "Box" ? 'class Box{public function new(){}public function read():Int{return 7;}}' : "")
				+ '@:native("console") extern class Console {public static function log(value:Dynamic):Void;}'
				+ 'class Main{static var calls:Int=0;public static var value('
				+ (writing ? "never,set" : "get,never")
				+ '):'
				+ entry.field
				+ ';'
				+ 'static function '
				+ (writing ? 'set_value(v:' + entry.input + ')' : 'get_value()')
				+ (entry.result == "" ? "" : ':' + entry.result)
				+ '{calls++;return '
				+ entry.body
				+ ';}'
				+ 'static function main(){var result='
				+ (writing ? '(value=3)' : 'value')
				+ ';Console.log('
				+ (entry.field == "Box" ? "result.read()" : "result")
				+ ');Console.log(calls);}}';
			sys.io.File.saveContent(path, source);
			final upstream = run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
			if ((upstream.code == 0) != entry.valid)
				throw "upstream accessor signature differs: " + entry.name + upstream.stderr;
			var typed:Null<TypedModule> = null;
			var error = "";
			try {
				final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
				typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			} catch (failure:haxe.Exception) {
				error = failure.message;
			}
			if (!entry.valid) {
				if (typed != null || error.indexOf("Property accessor signature differs") < 0)
					throw "invalid accessor signature was not rejected: " + entry.name + error;
			} else {
				if (typed == null)
					throw "valid accessor signature was rejected: " + entry.name + error;
				var accessorCalls = 0;
				function inspect(expression:TypedExpr):Void {
					if (expression.getTag() == Cast && expression.getTexts()[0] != "")
						throw "property assignment introduced a runtime-checked cast";
					final declaration = expression.getDeclaration();
					if (expression.getTag() == Call
						&& declaration != null
						&& declaration.getSignature().getName() == (writing ? "set_value" : "get_value")) {
						accessorCalls++;
						final result = TyType.fromHintText(entry.result == "" ? "Int" : entry.result);
						if (expression.getType().getSemanticKey() != result.getSemanticKey())
							throw "property conversion erased accessor result: " + entry.name;
						if (writing
							&& expression.getExpressions()[1].getType().getSemanticKey() != TyType.fromHintText(entry.input).getSemanticKey())
							throw "setter argument did not retain its selected input type";
					}
					for (child in expression.getExpressions())
						inspect(child);
				}
				for (owner in typed.getTypedClasses())
					for (method in owner.getFunctions())
						for (statement in method.getBody().getStatements())
							for (expression in statement.getExpressions())
								inspect(expression);
				if (accessorCalls != 1)
					throw "property did not select exactly one accessor";
				new backend.js.JsBackend().emit(new MacroExpandedProgram([typed], false),
					new backend.BackendContext(root, root + "/native.js", "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
				for (file in ["upstream.js", "native.js"]) {
					final result = run("node", [root + "/" + file]);
					if (result.code != 0 || result.stdout != "7\n1\n")
						throw "property runtime differs: " + entry.name + file + result.stdout + result.stderr;
				}
			}
			Sys.println("PROPERTY_SIGNATURE:PASS " + entry.name);
		}
	}

	/** Observe each compiler and runtime exit independently. */
	static function run(command:String, arguments:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}
}
