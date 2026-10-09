/** An unchecked authored cast gets its destination context without changing its operand type. */
class M14ContextualAuthoredCastTest {
	static function main():Void {
		final source = "class Main { static var box:Box<Int> = 7; static var plain:Int = cast box;"
			+ "static var grouped:Int = (cast box); static function output(value:Int):Void {}"
			+ "static function result(value:Box<Int>):Int { return cast value; } static function consume(value:Box<Int>):Void {}"
			+
			"static function main():Void { var local:Int = cast box; output(cast box); consume(cast 9); local = cast box; plain = (cast box); } } abstract Box<T>(T) from T {}";
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		var casts = 0;
		var location = "";
		function expression(value:TypedExpr):Void {
			if (value.getTag() == Cast && value.getTexts()[0] == "") {
				casts++;
				final input = value.getExpressions()[0];
				final enteringAbstract = input.getTag() == IntValue && input.getIntValue() == 9;
				final expected = enteringAbstract ? "nominal:Main.Box<primitive:Int>" : "primitive:Int";
				if (value.getType().getSemanticKey() != expected)
					throw "authored cast lost its destination context in " + location + ": " + value.getType().getSemanticKey();
				if (input.getType().getSemanticKey() != (enteringAbstract ? "primitive:Int" : "nominal:Main.Box<primitive:Int>"))
					throw "destination context changed the cast operand";
				if (value.isRepresentationPreservingCast())
					throw "authored cast borrowed an implicit conversion guarantee";
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
		for (owner in typed.getTypedClasses()) {
			for (initializer in owner.getFieldInitializers()) {
				location = initializer.getField().getName();
				expression(initializer.getExpression());
			}
			for (method in owner.getFunctions())
				for (child in method.getBody().getStatements()) {
					location = method.getStableIdentity() + "/" + Std.string(child.getTag());
					statement(child);
				}
		}
		if (casts != 8)
			throw "missing contextual cast coverage: " + casts;
		Sys.println("CONTEXTUAL_AUTHORED_CAST:PASS");
		fieldInference();
		genericExternField();
	}

	/** A generic extern call keeps its caller's result binder while contextualizing only the cast field. */
	static function genericExternField():Void {
		final source = "extern class Factory {public static function produce<T>(value:{}):T;}"
			+ "class Main {public static function forward<T>(value:Class<T>):T{return Factory.produce((cast value).data);}"
			+ "static function main():Void{}}";
		final root = ".tmp/contextual-cast-generic-extern";
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + "/Main.hx", source);
		// This extern is a declaration-only contract; eval cannot link its host implementation.
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/out.js"]);
		final output = upstream.stdout.readAll().toString();
		final error = upstream.stderr.readAll().toString();
		final status = upstream.exitCode();
		upstream.close();
		if (status != 0 || output != "" || error != "")
			throw "upstream generic extern cast differs: " + output + error;
		final resolved = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(source, root + "/Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		var calls = 0;
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				if (fn.getDeclaration().getSignature().getName() == "forward") {
					final signature = fn.getDeclaration().getSignature();
					function inspect(expression:TypedExpr):Void {
						if (expression.getTag() == Call) {
							calls++;
							if (expression.getNamedArguments() == null
								|| expression.getType().getSemanticKey() != signature.getReturnType().getSemanticKey())
								throw "generic extern cast call lost its selected binding or caller result";
						}
						if (expression.getTag() == Cast
							&& (expression.getType().getSemanticKey() != "anonymous:{data:anonymous:{}}"
								|| expression.getExpressions()[0].getType().getSemanticKey() != signature.getArgs()[0].getSemanticKey()))
							throw "generic extern cast changed its operand or lost field context";
						for (child in expression.getExpressions())
							inspect(child);
					}
					for (statement in fn.getBody().getStatements())
						for (expression in statement.getExpressions())
							inspect(expression);
				}
		if (calls != 1)
			throw "generic extern cast fixture missed its call";
		Sys.println("CAST_GENERIC_EXTERN_FIELD:PASS");
	}

	/** Field context must constrain the cast result, including aliases, while leaving its operand untouched. */
	static function fieldInference():Void {
		for (entry in [
			{
				name: "noncallable",
				body: "var alias=cast holder;var a:Int=alias.run;return alias.run(7);",
				output: "",
				accepted: false
			},
			{
				name: "call",
				body: "return (cast holder).run(7);",
				output: "8\n",
				accepted: true
			},
			{
				name: "call_alias",
				body: "var alias=cast holder;return alias.run(7);",
				output: "8\n",
				accepted: true
			},
			{
				name: "call_conflict",
				body: "var alias=cast holder;alias.run(7);return alias.run(\"bad\");",
				output: "",
				accepted: false
			},
			{
				name: "call_result_conflict",
				body: "var alias=cast holder;var a:Int=alias.run(7);var b:String=alias.run(7);return b;",
				output: "",
				accepted: false
			},
			{
				name: "direct",
				body: "return take((cast holder).value);",
				output: "7\n",
				accepted: true
			},
			{
				name: "alias",
				body: "var alias=cast holder;return take(alias.value);",
				output: "7\n",
				accepted: true
			},
			{
				name: "effects",
				body: "var alias=cast fresh(holder);return take(alias.value);",
				output: "7\n1\n",
				accepted: true
			},
			{
				name: "independent",
				body: "take((cast holder).value);return text((cast holder).other);",
				output: "word\n",
				accepted: true
			},
			{
				name: "conflict",
				body: "var alias=cast holder;take(alias.value);return text(alias.value);",
				output: "",
				accepted: false
			}
		]) {
			final root = ".tmp/contextual-cast-field-" + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + "/Main.hx";
			// Dynamic is the authored foreign-data boundary under test, not a compiler implementation escape.
			final source = "class Main {static function take(value:{answer:Int}):Int{return value.answer;}"
				+ "static function text(value:{answer:String}):String{return value.answer;}"
				+ "static var count:Int=0;static function fresh(value:Dynamic):Dynamic{count++;return value;}"
				+ "static function inspect(holder:Dynamic):Dynamic{"
				+ entry.body
				+ "}"
				+ "static function main():Void{Sys.println(inspect({value:{answer:7},other:{answer:\"word\"},run:function(value:Int):Int{return value+1;}}));"
				+ (entry.name == "effects" ? "Sys.println(count);" : "")
				+ "}}";
			sys.io.File.saveContent(path, source);
			final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]);
			final output = upstream.stdout.readAll().toString();
			final error = upstream.stderr.readAll().toString();
			final status = upstream.exitCode();
			upstream.close();
			if ((status == 0) != entry.accepted
				|| (entry.accepted ? output != entry.output || error.length != 0 : error.indexOf("should be") < 0
					&& !(entry.name == "noncallable" && error.indexOf("cannot be called") >= 0)))
				throw "upstream cast-field contract differs: " + entry.name + output + error;
			final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			var typed:Null<TypedModule> = null;
			try {
				typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
			} catch (error:TyperError) {
				if (entry.accepted)
					throw error;
			}
			if ((typed != null) != entry.accepted)
				throw "local cast-field acceptance differs: " + entry.name;
			if (typed != null) {
				var casts = 0;
				function inspect(expression:TypedExpr):Void {
					if (expression.getTag() == Cast && expression.getTexts()[0] == "") {
						casts++;
						if (!expression.getType().isAnonymous()
							|| expression.getType().hasUnknownComponent()
							|| !expression.getExpressions()[0].getType().isDynamic()
							|| expression.isRepresentationPreservingCast())
							throw "cast result lost its independent structural context: " + entry.name;
					}
					for (child in expression.getExpressions())
						inspect(child);
				}
				for (owner in typed.getTypedClasses())
					for (fn in owner.getFunctions())
						for (statement in fn.getBody().getStatements())
							for (expression in statement.getExpressions())
								inspect(expression);
				if (casts != (entry.name == "independent" ? 2 : 1))
					throw "cast-field fixture missed its authored casts";
				JsRuntimeFixture.assertRuntime(typed, "Main", entry.output);
			}
			Sys.println("CAST_FIELD_INFERENCE:PASS " + entry.name);
		}
	}
}
