import backend.BackendContext;
import backend.BackendRegistry;

/** Compare real native conditional conversion effects with an independently specified contract. */
class M14ConditionalAbstractResultTest {
	/** A declared destination must not invent conversions or erase null/dynamic source facts. */
	static function rejectedContexts():Void {
		final resolved = new ResolvedModule("Negative", "Negative.hx", ParserStage.parse("abstract Opaque(Int) from Int {} class Negative {}", "Negative.hx"));
		final index = TyperIndex.build([resolved]);
		final opaque = TyType.nominal(index.getAbstractByFullName("Negative.Opaque").getIdentity(), []);
		final integer = TyType.fromHintText("Int");
		for (source in [opaque, TyType.fromHintText("Dynamic")]) {
			final result = TyConditionalResult.join(source, integer, integer, index);
			if (result != null && result.getSemanticKey() == integer.getSemanticKey())
				throw "Conditional context invented a conversion for " + source.getSemanticKey();
		}
		final nullable = TyConditionalResult.join(integer, TyType.fromHintText("Null"), integer, index);
		if (nullable == null || !nullable.isNullable() || nullable.unwrapNull().getSemanticKey() != integer.getSemanticKey())
			throw "Conditional destination erased the null branch";
	}

	/** The shared tree must retain the result and conversions before any target receives it. */
	static function typedBranches(module:TypedModule):Void {
		var checked = 0;
		for (owner in module.getTypedClasses())
			for (fn in owner.getFunctions()) {
				final name = HxFunctionDecl.getName(fn.getSourceDeclaration());
				if (["choose", "effect", "branch", "grouped", "nested"].indexOf(name) < 0)
					continue;
				final value = fn.getBody().getStatements()[0].getExpressions()[0];
				if (value.getType().getSemanticKey() != "primitive:Int")
					throw "Conditional lost its declared result: " + name;
				final branches = value.getExpressions();
				if (branches.length != 3
					|| branches[1].getType().getSemanticKey() != "primitive:Int"
					|| branches[2].getType().getSemanticKey() != "primitive:Int")
					throw "Conditional branch conversion is absent: " + name;
				checked++;
			}
		if (checked != 5)
			throw "Conditional typed contracts were not all inspected";
	}

	static function main():Void {
		rejectedContexts();
		final fixture = "test/fixtures/conditional_abstract_result/";
		final files = [
			{name: "Main", path: fixture + "Main.hx"},
			{name: "Sys", path: "test/fixtures/cpp_static_callable/Sys.hx"}
		];
		final resolved = [
			for (file in files)
				new ResolvedModule(file.name, file.path, ParserStage.parse(sys.io.File.getContent(file.path), file.path))
		];
		final index = TyperIndex.build(resolved);
		final typed = [for (module in resolved) TyperStage.typeResolvedModule(module, index)];
		typedBranches(typed[0]);
		final program = MacroStage.expandProgram(typed, []);
		final expected = sys.io.File.getContent(fixture + "expected.stdout");
		JsRuntimeFixture.assertProgramRuntime(program, "Main", expected);
		final result = BackendRegistry.createForTarget("cpp-native")
			.emit(program, new BackendContext(".tmp/conditional-abstract-result", null, "Main", true, new haxe.ds.StringMap()));
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (!result.builtExecutable || code != 0 || stdout != expected)
			throw "Conditional conversion changed values or effects: " + stdout + stderr;
		Sys.println("CONDITIONAL_ABSTRACT_RESULT:PASS");
	}
}
