import sys.io.File;

/** Constant initialization must preserve the abstract declaration without admitting outside assignments. */
class M14EnumAbstractInitializerTest {
	static final root = "test/fixtures/enum_abstract_initializers";

	static function program(source:String):TypedModule {
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
	}

	static function observe(command:String, arguments:Array<String>, ?expected:String):Void {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != (expected == null ? File.getContent(root + "/expected.stdout") : expected))
			throw "enum initializer observer mismatch: " + stdout + stderr;
	}

	static function rejects(source:String):Void {
		var rejected = false;
		try {
			program(source);
		} catch (_:TyperError) {
			rejected = true;
		}
		if (!rejected)
			throw "invalid abstract assignment accepted";
	}

	static function main():Void {
		Sys.putEnv("HXHX_TYPER_STRICT", "1");
		nullConstants();
		final typed = program(File.getContent(root + "/Main.hx"));
		var count = 0;
		for (owner in typed.getTypedClasses())
			for (initializer in owner.getFieldInitializers()) {
				final field = initializer.getField();
				if (!field.getConstant().isEnumValue())
					continue;
				count++;
				final expression = initializer.getExpression();
				if (expression.getType().getSemanticKey() != field.getType().getSemanticKey())
					throw "initializer erased its abstract type";
				if (expression.getTag() == Cast && !expression.isRepresentationPreservingCast())
					throw "enum constant needs a proven value-preserving conversion";
			}
		if (count != 7)
			throw "enum initializer inventory mismatch: " + count;
		rejects('enum abstract Signal(Int) { var Red=10; } class Main { static var invalid:Signal=10; }');
		rejects('enum abstract Signal(Int) { var Red=10; } class Main { static function invalid():Signal return 10; }');
		rejects('enum abstract Signal(Int) { var Red="bad"; } class Main {}');
		observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"]);
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/enum-abstract-initializers");
		observe(executable, []);
		Sys.println("ENUM_ABSTRACT_INITIALIZER:PASS");
	}

	/** Null has resolved constant evidence, but each initializer still has its declared abstract type. */
	static function nullConstants():Void {
		final fixture = "test/fixtures/enum_abstract_null_constants";
		final expected = File.getContent(fixture + "/expected.stdout");
		observe("node_modules/.bin/haxe", ["-cp", fixture, "--run", "Main"], expected);
		final typed = M14Stage3RuntimeFixture.typeMain({source: File.getContent(fixture + "/Main.hx"), path: fixture + "/Main.hx", root: fixture});
		final nullIdentity = new TyFieldConstant(NullValue).getCanonicalIdentity();
		if (nullIdentity == new TyFieldConstant(Ordinary).getCanonicalIdentity()
			|| nullIdentity == new TyFieldConstant(StringValue("null")).getCanonicalIdentity()
				|| nullIdentity == new TyFieldConstant(Unresolved("missing")).getCanonicalIdentity())
			throw "null constant identity collides with absent or different evidence";
		var count = 0;
		for (owner in typed.getTypedClasses())
			for (initializer in owner.getFieldInitializers()) {
				final field = initializer.getField();
				if (!field.getConstant().getKind().match(NullValue))
					continue;
				count++;
				if (!field.getConstant().project().match(ENull) || field.getConstant().getCanonicalIdentity() != nullIdentity)
					throw "null constant lost its projected value or alias identity";
				if (initializer.getExpression().getType().getSemanticKey() != field.getType().getSemanticKey())
					throw "null initializer erased its enum-abstract type";
			}
		if (count != 5)
			throw "null constant inventory mismatch: " + count;
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		Sys.println("ENUM_ABSTRACT_NULL_JS:PASS");
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/enum-abstract-null-constants");
		observe(executable, [], expected);
		Sys.println("ENUM_ABSTRACT_NULL_NATIVE:PASS");
	}
}
