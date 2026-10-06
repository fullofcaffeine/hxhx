/** Ordinary Dynamic calls retain their result permission without granting it to unresolved or known incompatible calls. */
class M14DynamicCallResultTest {
	static function main():Void {
		for (entry in [
			{
				name: "inferred_field",
				field: "static var callback=load();",
				body: "trace(take(callback(7)));",
				output: "word\n",
				calls: 1
			},
			{
				name: "written_field",
				field: "static var callback:Dynamic=load();",
				body: "trace(take(callback(7)));",
				output: "word\n",
				calls: 1
			},
			{
				name: "local",
				field: "",
				body: "var callback:Dynamic=load();trace(take(callback(7)));",
				output: "word\n",
				calls: 1
			},
			{
				name: "lambda",
				field: "",
				body: 'var callback:Dynamic=function(value:Int):String{return "word";};trace(take(callback(7)));',
				output: "word\n",
				calls: 1
			},
			{
				name: "instance",
				field: "",
				body: "var holder=new Holder(load());trace(take(holder.callback(7)));",
				output: "word\n",
				calls: 1
			},
			{
				name: "record",
				field: "",
				body: "var holder:{callback:Dynamic}={callback:load()};trace(take(holder.callback(7)));",
				output: "word\n",
				calls: 1
			},
			{
				name: "record_returned",
				field: "",
				body: "trace(take(record().callback(7)));",
				output: "word\n",
				calls: 1
			},
			{
				name: "qualified",
				field: "static var callback:Dynamic=load();",
				body: "trace(take(Main.callback(7)));",
				output: "word\n",
				calls: 1
			},
			{
				name: "returned",
				field: "",
				body: "trace(take(load()(7)));",
				output: "word\n",
				calls: 1
			},
			{
				name: "effects",
				field: "",
				body: "trace(take(acquire()(argument())));trace(events);",
				output: "word\ncar\n",
				calls: 1
			},
			{
				name: "block_argument",
				field: "",
				body: 'var callback:Dynamic=load();trace(take(callback({events+="a";7;})));trace(events);',
				output: "word\nar\n",
				calls: 1
			}
		]) {
			final source = 'class Holder{public var callback:Dynamic;public function new(callback:Dynamic){this.callback=callback;}}'
				+ 'class Main{static function load():Dynamic{return function(value:Int):String{return "word";};}'
				+ 'static function record():{callback:Dynamic}{return {callback:load()};}'
				+ 'static var events:String="";static function acquire():Dynamic{events+="c";return load();}'
				+ 'static function argument():Int{events+="a";return 7;}'
				+ entry.field
				+ 'static function take(value:String):String{events+="r";return value;}static function main():Void{'
				+ entry.body
				+ '}}';
			final path = write(entry.name, source);
			upstream(path, entry.output);
			final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			typed.getBackendProjection();
			var calls = 0;
			function expression(value:TypedExpr):Void {
				if (value.getTag() == Call && value.getExpressions()[0].getType().isDynamic()) {
					if (!value.getType().isDynamic())
						throw "Dynamic invocation lost its result type";
					calls++;
				}
				for (child in value.getExpressions())
					expression(child);
			}
			function statement(value:TypedStmt):Void {
				for (child in value.getExpressions())
					expression(child);
				for (child in value.getStatements())
					statement(child);
			}
			for (owner in typed.getTypedClasses())
				for (fn in owner.getFunctions())
					if (fn.getDeclaration().getSignature().getName() == "main")
						for (body in fn.getBody().getStatements())
							statement(body);
			if (calls != entry.calls)
				throw "Dynamic invocation observer missed a call: " + entry.name;
			JsRuntimeFixture.assertRuntime(typed, "Main", entry.output);
			Sys.println("DYNAMIC_CALL_RESULT:PASS " + entry.name);
		}
		for (entry in [
			{name: "known", body: 'var callback:Int->String=function(value:Int):String{return "word";};take(callback("wrong"));'},
			{name: "known_untyped", body: 'var callback:Int->String=function(value:Int):String{return "word";};untyped take(callback("wrong"));'},
			{name: "missing", body: 'take(missing(7));'}
		]) {
			final source = 'class Main{static function take(value:String):Void{}static function main():Void{' + entry.body + '}}';
			final path = write(entry.name, source);
			upstream(path, null);
			var rejected = false;
			try {
				final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
				TyperStage.typeResolvedModule(module, TyperIndex.build([module])).getBackendProjection();
			} catch (error:haxe.Exception) {
				rejected = error.message.indexOf("should be") >= 0
					|| error.message.indexOf("compatible") >= 0
					|| error.message.indexOf("unresolved") >= 0
					|| error.message.indexOf("unknown") >= 0;
				if (!rejected)
					throw error;
			}
			if (!rejected)
				throw "Dynamic call repair admitted a strict error: " + entry.name;
			Sys.println("DYNAMIC_CALL_RESULT:PASS " + entry.name);
		}
	}

	/** Each source has a distinct path so one case cannot reuse another case's compiler output. */
	static function write(name:String, source:String):String {
		final root = ".tmp/dynamic-call-result-" + name;
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		return path;
	}

	/** Null output denotes a compile-time rejection; successful cases must match independent runtime expectations. */
	static function upstream(path:String, expected:Null<String>):Void {
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		final process = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler,
			["-cp", haxe.io.Path.directory(path), "-main", "Main", "--interp"]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (expected == null) {
			if (code == 0 || (errors.indexOf("should be") < 0 && errors.indexOf("Unknown identifier") < 0))
				throw "upstream accepted or misdiagnosed invalid call: " + output + errors;
		} else {
			final printed = expected.split("\n")
				.filter(line -> line.length > 0)
				.map(line -> path + ":1: " + line + "\n")
				.join("");
			if (code != 0 || output != printed || errors.length != 0)
				throw "upstream Dynamic call differs: " + output + errors;
		}
		Sys.println("DYNAMIC_CALL_RESULT_UPSTREAM:PASS " + path);
	}
}
