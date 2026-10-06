import sys.io.File;

/** Stored generic calls retain final argument proofs without widening the actual operand type. */
class M14CapturedCallbackPublicationTest {
	static function main():Void {
		final declarations = 'class Base<T>{public function new(){}}class Child extends Base<String>{public function new(){super();}}class Receiver{public function new(){}public function echo<T>(value:T):T{return value;}}';
		check("subtype",
			declarations +
			'class Main{static function main():Void{var receiver=new Receiver();var callback:Base<String>->Base<String>=receiver.echo;var result=callback(new Child());Sys.println(result!=null);}}',
			"true\n", true);
		check("generic_conflict",
			declarations +
			'class Main{static function main():Void{var receiver=new Receiver();var callback:Base<Int>->Base<Int>=receiver.echo;callback(new Child());}}',
			null);
		check("reverse",
			declarations +
			'class Main{static function main():Void{var receiver=new Receiver();var callback:Child->Child=receiver.echo;callback(new Base<String>());}}',
			null);
		check("late_alias",
			'class Receiver{public function new(){}public function echo<T>(?value:T):Null<T>{return value;}}class Main{static function main():Void{var receiver=new Receiver();var callback=receiver.echo;var alias=callback;Sys.println(callback()==null);Sys.println(alias("value"));}}',
			"true\nvalue\n");
	}

	/** Upstream decisions precede local typing; accepted programs must also execute in generated JavaScript. */
	static function check(name:String, source:String, expected:Null<String>, inspectSubtype:Bool = false):Void {
		final root = ".tmp/captured_callback_publication_" + name;
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		File.saveContent(path, source);
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]);
		final stdout = upstream.stdout.readAll().toString();
		final stderr = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (expected == null ? code == 0 || stderr.indexOf("should be") < 0 : code != 0 || stdout != expected)
			throw "upstream captured callback contract differs for " + name + ": " + stdout + stderr;
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		var typed:Null<TypedModule> = null;
		try {
			typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		} catch (message:String) {
			if (expected != null || message != "captured callback argument conflicts with its inferred type")
				throw message;
		}
		if (expected == null) {
			if (typed != null)
				throw "invalid captured argument was accepted: " + name;
		} else {
			if (typed == null)
				throw "valid captured callback was rejected: " + name;
			if (inspectSubtype) {
				var observed = 0;
				function inspect(node:TypedExpr):Void {
					final binding = node.getArgumentBinding();
					if (binding != null) {
						final parameters = binding.getFunctionType().getFunctionArguments();
						final operands = binding.getOperandTypes();
						if (parameters.length == 1
							&& operands.length == 1
							&& parameters[0].getSemanticKey() == "nominal:Main.Base<primitive:String>"
							&& operands[0].getSemanticKey() == "nominal:Main.Child")
							observed++;
					}
					for (child in node.getExpressions())
						inspect(child);
				}
				for (owner in typed.getTypedClasses())
					for (fn in owner.getFunctions())
						for (statement in fn.getBody().getStatements())
							for (node in statement.getExpressions())
								inspect(node);
				if (observed != 1)
					throw "captured subtype call lost its exact parameter or operand type";
			}
			JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		}
		Sys.println("CAPTURED_CALLBACK_PUBLICATION:PASS " + name);
	}
}
