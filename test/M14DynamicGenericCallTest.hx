/** Explicit Dynamic operands supply a late fallback while later concrete uses still constrain each generic call. */
class M14DynamicGenericCallTest {
	static function main():Void {
		final helpers = 'class Main{static function fixed<T>(left:T,right:T):Int{return 0;}'
			+ 'static function echo<T>(value:T):T{return value;}static function choose<T>(left:T,right:T):T{return left;}'
			+ 'static function bound<T:String>(value:T):Int{return 1;}'
			+ 'static function boundEcho<T:String>(value:T):T{return value;}'
			+ 'static function boundRest<T:String>(...values:T):T{return values[0];}'
			+ 'static function rest<T>(...values:T):Int{return values.length;}'
			+ 'static function optional<T>(value:T,?unused:Int):Int{return 2;}'
			+ 'static var events:String="";static function next(value:Int):Dynamic{events+=value;return value;}';
		for (entry in [
			{
				name: "bound_rest_result",
				body: 'var value:String=boundRest(text,text);trace(value);',
				output: "word\n",
				accepted: true
			},
			{
				name: "bound_rest_context_negative",
				body: 'var value:Int=boundRest(n,n);trace(value);',
				output: "",
				accepted: false
			},
			{
				name: "bound_result",
				body: 'var value:String=boundEcho(text);trace(value);',
				output: "word\n",
				accepted: true
			},
			{
				name: "bound_context_negative",
				body: 'var value:Int=boundEcho(n);trace(value);',
				output: "",
				accepted: false
			},
			{
				name: "effects",
				body: 'trace(fixed(next(1),next(2)));trace(events);',
				output: "0\n12\n",
				accepted: true
			},
			{
				name: "block_arguments",
				body: 'var value=fixed({var x:Dynamic=7;x;},{var y:Dynamic=8;y;});trace(value);',
				output: "0\n",
				accepted: true
			},
			{
				name: "fixed",
				body: 'trace(fixed(n,n));',
				output: "0\n",
				accepted: true
			},
			{
				name: "echo",
				body: 'trace(echo(n));',
				output: "7\n",
				accepted: true
			},
			{
				name: "mixed_first",
				body: 'trace(choose(n,7));',
				output: "7\n",
				accepted: true
			},
			{
				name: "mixed_last",
				body: 'trace(choose(7,n));',
				output: "7\n",
				accepted: true
			},
			{
				name: "later",
				body: 'var value=echo(n);var alias=value;var typed:Int=alias;trace(typed);',
				output: "7\n",
				accepted: true
			},
			{
				name: "independent",
				body: 'var first:Int=echo(n);var second:String=echo(text);trace(first);trace(second);',
				output: "7\nword\n",
				accepted: true
			},
			{
				name: "bound",
				body: 'trace(bound(text));',
				output: "1\n",
				accepted: true
			},
			{
				name: "rest",
				body: 'trace(rest(n,n));',
				output: "2\n",
				accepted: true
			},
			{
				name: "optional",
				body: 'trace(optional(n));',
				output: "2\n",
				accepted: true
			},
			{
				name: "conflict",
				body: 'var value=echo(n);var first:Int=value;var second:String=value;',
				output: "",
				accepted: false
			},
			{
				name: "incompatible",
				body: 'trace(fixed(7,"word"));',
				output: "",
				accepted: false
			},
			{
				name: "bound_negative",
				body: 'trace(bound(7));',
				output: "",
				accepted: false
			},
			{
				name: "blocks",
				body: 'trace(fixed({var x:Dynamic=7;x;},{var y:Dynamic=8;y;}));',
				output: "0\n",
				accepted: true
			}
		]) {
			final root = ".tmp/dynamic-generic-call-" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			final source = helpers + 'static function main():Void{var n:Dynamic=7;var text:Dynamic="word";' + entry.body + '}}';
			sys.io.File.saveContent(path, source);
			final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
			final upstream = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]);
			final stdout = upstream.stdout.readAll().toString();
			final stderr = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			final expected = entry.output.split("\n")
				.filter(line -> line.length > 0)
				.map(line -> path + ":1: " + line + "\n")
				.join("");
			if ((code == 0) != entry.accepted
				|| (entry.accepted ? stdout != expected || stderr.length != 0 : stderr.indexOf("should be") < 0))
				throw "upstream generic Dynamic contract differs: " + entry.name + stdout + stderr;
			var typed:Null<TypedModule> = null;
			try {
				final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
				typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
				typed.getBackendProjection();
			} catch (error:haxe.Exception) {
				if (entry.accepted)
					throw error;
				if (error.message.indexOf("conflict") < 0
					&& error.message.indexOf("not compatible") < 0
					&& error.message.indexOf("No compatible") < 0
					&& error.message.indexOf("Constraint check failure") < 0)
					throw "generic rejection lost its type diagnostic: " + error.message;
				typed = null;
			}
			if ((typed != null) != entry.accepted)
				throw "local generic Dynamic acceptance differs: " + entry.name;
			if (typed != null) {
				final results = switch entry.name {
					case "bound_result" | "bound_rest_result": ["primitive:String"];
					case "echo": ["dynamic"];
					case "independent": ["primitive:Int", "primitive:String"];
					case _: ["primitive:Int"];
				};
				assertPublished(typed, results);
				JsRuntimeFixture.assertRuntime(typed, "Main", entry.output);
			}
			Sys.println("DYNAMIC_GENERIC_CALL:PASS " + entry.name);
		}
	}

	/** Sealed main-call arguments must be known without replacing the operands' explicit Dynamic types. */
	static function assertPublished(module:TypedModule, results:Array<String>):Void {
		var checked = 0;
		function expression(value:TypedExpr):Void {
			final declaration = value.getDeclaration();
			if (value.getTag() == Call && declaration != null && declaration.getTypeParameterIds().length > 0) {
				final named = value.getNamedArguments();
				if (named == null)
					throw "generic call lost its selected argument binding";
				final callable = named.getArguments().getFunctionType();
				if (callable.hasUnknownComponent() || callable.hasOpenMethodParameter())
					throw "generic call published an open callable: " + callable.getSemanticKey();
				if (checked >= results.length || value.getType().getSemanticKey() != results[checked])
					throw "generic result lost its later concrete context: " + value.getType().getSemanticKey();
				value.assertArgumentBinding();
				checked++;
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
		for (owner in module.getTypedClasses())
			for (fn in owner.getFunctions())
				if (fn.getDeclaration().getSignature().getName() == "main")
					for (body in fn.getBody().getStatements())
						statement(body);
		if (checked != results.length)
			throw "generic call observation missed the main body";
	}
}
