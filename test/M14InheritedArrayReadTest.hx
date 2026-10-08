/** Declared Array ancestors supply indexed element types without erasing the concrete host receiver. */
class M14InheritedArrayReadTest {
	static function main():Void {
		check();
	}

	public static function check():Void {
		for (entry in [
			{name: "direct", parents: "", parent: "Array<String>"},
			{name: "generic", parents: "extern class Base<T> extends Array<T>{}", parent: "Base<String>"},
			{name: "reordered", parents: "extern class Base<A,B> extends Array<B>{}extern class Middle<T> extends Base<Int,T>{}", parent: "Middle<String>"}
		]) {
			final root = ".tmp/inherited_array_read_" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			final source = entry.parents
				+ 'extern class Items extends '
				+ entry.parent
				+ '{public var index:Int;}'
				+ 'extern class GenericItems<T> extends Array<T>{}'
				+
				'@:native("Host")extern class Host{public static function input():Items;public static function take(value:Int):Void;public static function offset():Int;}'
				+ 'class Main{static function first<T>(value:GenericItems<T>):T{return value[0];}'
				+ 'static function main():Void{var items=Host.input();var size=items.index+items[Host.offset()].length;Host.take(10-size);}}';
			sys.io.File.saveContent(path, source);
			final upstream = run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
			if (upstream.code != 0)
				throw "upstream inherited array failed: " + upstream.stderr;
			final typed = type(source, path);
			var reads = 0;
			var genericReads = 0;
			function inspect(expression:TypedExpr):Void {
				if (expression.getTag() == ArrayAccess) {
					final receiver = expression.getExpressions()[0].getType();
					final identity = receiver.getNominalIdentity();
					if (identity == null)
						throw "indexed read lost its concrete receiver";
					if (identity.getCanonicalName() == "Main.Items") {
						reads++;
						if (expression.getType().getSemanticKey() != "primitive:String")
							throw "inherited indexed read lost String";
					} else if (identity.getCanonicalName() == "Main.GenericItems") {
						genericReads++;
						if (expression.getType().getTypeParameterIdentity() == null
							|| expression.getType().getSemanticKey() != receiver.getTypeArguments()[0].getSemanticKey())
							throw "inherited indexed read lost its exact generic binder";
					}
				}
				for (child in expression.getExpressions())
					inspect(child);
			}
			for (owner in typed.getTypedClasses())
				for (method in owner.getFunctions())
					for (statement in method.getBody().getStatements())
						for (expression in statement.getExpressions())
							inspect(expression);
			if (reads != 1 || genericReads != 1)
				throw "inherited array fixture missed its reads";
			final harness = root + "/host.cjs";
			sys.io.File.saveContent(harness,
				'let inputs=0,offsets=0,reads=0,takes=0;const values=[];values.index=2;Object.defineProperty(values,"0",{get(){reads++;return "word";}});' +
				'global.Host={input(){inputs++;return values;},offset(){offsets++;return 0;},take(value){takes++;if(value!==4)throw Error("offset result");}};' +
				'require(process.argv[2]);if(inputs!==1||offsets!==1||reads!==1||takes!==1)throw Error("evaluation count");console.log("ok");');
			new backend.js.JsBackend().emit(new MacroExpandedProgram([typed], false),
				new backend.BackendContext(root, root + "/native.js", "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
			for (file in ["upstream.js", "native.js"]) {
				final result = run("node", [harness, sys.FileSystem.fullPath(root + "/" + file)]);
				if (result.code != 0 || result.stdout != "ok\n")
					throw "inherited array runtime differs: " + entry.name + file + result.stdout + result.stderr;
			}
			Sys.println("INHERITED_ARRAY_READ:PASS " + entry.name);
		}
		for (entry in [
			{name: "wrong_element", declaration: "extern class Items extends Array<String>{}", value: "Host.input()[0]"},
			{
				name: "unrelated",
				declaration: "extern class Other<T>{public var index:Int;}typedef Items=Other<String>;",
				value: "10-(Host.input().index+Host.input()[0].length)"
			}
		]) {
			final root = ".tmp/inherited_array_read_" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			final source = entry.declaration
				+ 'extern class Host{public static function input():Items;public static function take(value:Int):Void;}'
				+ 'class Main{static function main():Void{Host.take('
				+ entry.value
				+ ');}}';
			sys.io.File.saveContent(path, source);
			if (run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/invalid.js"]).code == 0)
				throw "upstream accepted invalid indexed input: " + entry.name;
			var rejected = false;
			try {
				type(source, path);
			} catch (error:haxe.Exception) {
				rejected = error.message.indexOf("No compatible method signature") >= 0
					|| error.message.indexOf("selected call conversion does not satisfy") >= 0;
			}
			if (!rejected)
				throw "invalid indexed input accepted: " + entry.name;
			Sys.println("INHERITED_ARRAY_READ:PASS " + entry.name);
		}
	}

	/** Real Array and String declarations provide the target's actual read contracts. */
	static function type(source:String, path:String):TypedModule {
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final args = hxhx.Stage1Compiler.Stage1Args.parse(["-main", "Main"], true);
		final standardRoot = hxhx.Stage1Compiler.Stage1Args.getStandardLibraryRoot(args);
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader([standardRoot + "/js/_std", standardRoot], hxhx.Stage3SetupSupport.buildDefinesMap([], "js", "js-native"), index,
			null, true);
		loader.markResolvedAlready([module]);
		if (loader.ensureTypeAvailable("String", "", []) == null || loader.ensureTypeAvailable("Array", "", []) == null)
			throw "missing authentic array/string provider";
		return TyperStage.typeResolvedModule(module, index, loader, true);
	}

	/** Observe actual compiler and runtime results without inferring success from generated text. */
	static function run(command:String, arguments:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}
}
