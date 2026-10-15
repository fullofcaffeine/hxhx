import sys.io.File;

/** Compare native short-circuit effects and Boolean storage with an independent expected transcript. */
class M14DynamicBooleanControlTest {
	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	/** Same-spelled operands from another body cannot supply condition conversion facts. */
	static function ownership():Void {
		final source = "class Main { static var value:Dynamic = false; static var selected:String = value ? 'yes' : 'no'; "
			+ "static function probe(value:Dynamic):Int { if (value) return 1; return 2; } }";
		function projection():TypedBackendClassProjection {
			final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
			return TyperStage.typeResolvedModule(module, TyperIndex.build([module])).getBackendProjection().getClasses()[0];
		}
		final first = projection();
		final second = projection();
		final fn = first.getFunctions()[0];
		final foreign = second.getFunctions()[0];
		var count = 0;
		var selected:Null<HxExpr> = null;
		TypedBackendSourceWalk.functionDeclaration(fn.getDeclaration(), expression -> {
			final condition = fn.findCondition(expression);
			if (condition != null) {
				count++;
				selected = expression;
				require(condition.type.isDynamic(), "condition lost its Dynamic type");
				require(foreign.findCondition(expression) == null, "foreign function borrowed condition facts");
				switch expression {
					case EIdent(name): require(fn.findCondition(EIdent(name)) == null, "copied condition borrowed facts");
					case _: throw "expected a local condition";
				}
				var rejected = false;
				try {
					condition.assertCurrent("foreign", fn.getBodyRevision());
				} catch (error:String) {
					rejected = error.indexOf("another executable") >= 0;
				}
				require(rejected, "condition accepted a foreign revision owner");
			}
		}, _ -> {});
		var initializers = 0;
		for (initializer in first.getFieldInitializers())
			TypedBackendSourceWalk.expression(initializer.getExpression(), expression -> {
				final condition = initializer.findCondition(expression);
				if (condition != null) {
					initializers++;
					require(condition.type.isDynamic(), "initializer condition lost its Dynamic type");
					for (other in second.getFieldInitializers())
						require(other.findCondition(expression) == null, "foreign initializer borrowed condition facts");
				}
			});
		require(count == 1 && initializers == 1, "condition ownership controls were not exercised: functions="
			+ count
			+ " initializers="
			+ initializers);
		final body = fn.getBody();
		body.splice(0, body.length);
		var rejected = false;
		try {
			fn.findCondition(selected);
		} catch (error:String) {
			rejected = error.indexOf("mutated") >= 0;
		}
		require(rejected, "removed condition kept its conversion facts");
		Sys.println("DYNAMIC_BOOLEAN_OWNERSHIP:PASS");
	}

	public static function main():Void {
		ownership();
		final root = "test/fixtures/dynamic_boolean_control";
		final path = root + "/Main.hx";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("DYNAMIC_BOOLEAN_UPSTREAM:PASS");
		final typed = M14Stage3RuntimeFixture.typeMain({source: File.getContent(path), path: path, root: root});
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), ".tmp/dynamic_boolean_control", true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("DYNAMIC_BOOLEAN_NATIVE:PASS");
	}
}
