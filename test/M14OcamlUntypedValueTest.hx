import sys.io.File;

/** Unchecked scalar values retain exact storage and ownership through native emission. */
class M14OcamlUntypedValueTest {
	public static function run():Void {
		final root = ".tmp/m14_ocaml_untyped_value";
		sys.FileSystem.createDirectory(root);
		final source = 'class Main {'
			+ 'static var flag:Dynamic=untyped true;'
			+ 'static var word:Dynamic=untyped "value";'
			+ 'static function number():Dynamic{Sys.println("once");return 7;}'
			+ 'static function other():Void{}'
			+ 'static function main():Void{'
			+ 'var boolean:Bool=untyped flag;var text:String=untyped word;var integer:Int=untyped number();'
			+ 'Sys.println(boolean);Sys.println(text);Sys.println(integer);Sys.println(flag==1);}}';
		final expected = "once\ntrue\nvalue\n7\nfalse\n";
		final path = root + "/Main.hx";
		File.saveContent(path, source);
		M14Stage3RuntimeFixture.observe({command: "haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		ownership(typed);
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), root + "/ocaml", true, true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("OCAML_UNTYPED_VALUE:PASS");
	}

	/** Copied syntax, foreign owners, and replaced expressions cannot authorize a conversion. */
	static function ownership(typed:TypedModule):Void {
		final owners = typed.getBackendProjection().getClasses();
		final functions = [for (owner in owners) for (fn in owner.getFunctions()) fn];
		final main = functions.filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == "main")[0];
		final other = functions.filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == "other")[0];
		var conversions = 0;
		TypedBackendSourceWalk.functionDeclaration(main.getDeclaration(), expression -> {
			final facts = main.findUntyped(expression);
			if (facts == null)
				return;
			conversions++;
			if (!facts.getSourceType().isDynamic() || facts.getTargetType().isDynamic())
				throw "unchecked local lost its distinct producer and destination";
			final copy:HxExpr = EUntyped(facts.getOperand());
			if (main.findCast(expression) != null || main.findUntyped(copy) != null || other.findUntyped(expression) != null)
				throw "unchecked conversion borrowed a cast, copied expression, or foreign owner";
		}, _ -> {});
		if (conversions != 3)
			throw "unchecked local conversion coverage differs";
		final initializers = [for (owner in owners) for (field in owner.getFieldInitializers()) field];
		if (initializers.length != 2)
			throw "unchecked initializer coverage differs";
		for (field in initializers) {
			final expression = field.getExpression();
			final facts = field.findUntyped(expression);
			if (facts == null || !facts.getTargetType().isDynamic() || facts.getSourceType().isDynamic() || field.findCast(expression) != null)
				throw "unchecked initializer lost its distinct producer and destination";
			final copy:HxExpr = EUntyped(facts.getOperand());
			reject(() -> field.findUntyped(copy));
			final foreign = field == initializers[0] ? initializers[1] : initializers[0];
			reject(() -> foreign.findUntyped(expression));
		}
		final body = main.getBody();
		var replaced = false;
		for (index in 0...body.length)
			switch body[index] {
				case SVar(name, hint, expression, position, metadata) if (main.findUntyped(expression) != null):
					final original = body[index];
					final facts = main.findUntyped(expression);
					body[index] = SVar(name, hint, EUntyped(facts.getOperand()), position, metadata);
					reject(() -> main.findUntyped(expression));
					body[index] = original;
					replaced = true;
				case _:
			}
		if (!replaced)
			throw "unchecked conversion replacement control did not execute";
	}

	static function reject(action:Void->Void):Void {
		try {
			action();
		} catch (_:haxe.Exception) {
			return;
		}
		throw "unchecked conversion accepted a copied, foreign, or replaced occurrence";
	}

	static function main():Void
		run();
}
