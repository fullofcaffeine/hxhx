import backend.BackendContext;
import backend.BackendRegistry;
import backend.source.SourceFunctionBodyRewriter;

/** Prove enum switch result assignment with upstream behavior and real C# execution. */
class M14CsEnumSwitchResultTest {
	public static function main():Void {
		checkCoverageCopies();
		final root = ".tmp/cs_enum_switch_result_" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		final cases = [
			{name: "nested_postfix",
				source: "enum A { A1(v:String); A2(v:B); } enum B { BB(v:Float); } class Main { static function main() {"
				+ "var original = A2(BB(12)); var value = original;"
				+ "value = switch(value) { case A2(v): switch(v) { case BB(v): A2(BB(v++)); } default: A1(''); };"
				+ "switch(value) { case A2(BB(v)): Sys.println(v); default: Sys.println('wrong'); }"
				+ "switch(original) { case A2(BB(v)): Sys.println(v); default: Sys.println('mutated'); } } }",
				expected: "12\n12"
			},
			{
				name: "multiple_constructors",
				source: choiceProgram("var input = Second(7); var result = switch(input) {case First(v): v + 1; case Second(v): v + 2;}; Sys.println(result);"),
				expected: "9"
			},
			{
				name: "null_is_abrupt",
				source: choiceProgram("var input:Choice = null; try { var result = switch(input) {case First(v): v; case Second(v): v;}; Sys.println('unexpected'); } catch (e:Dynamic) { Sys.println('caught'); }"),
				expected: "caught"
			},
			{
				name: "throwing_arm",
				source: choiceProgram("var input = First(7); try { var result = switch(input) {case First(v): throw 'stop'; case Second(v): v;}; Sys.println('unexpected'); } catch (e:Dynamic) { Sys.println('caught'); }"),
				expected: "caught"
			}
		];
		for (entry in cases) {
			final directory = root + "/" + entry.name;
			sys.FileSystem.createDirectory(directory);
			sys.io.File.saveContent(directory + "/Main.hx", entry.source);
			expect(run("haxe", ["-cp", directory, "-main", "Main", "--interp"]), entry.expected);
			final module = new ResolvedModule("Main", directory + "/Main.hx", ParserStage.parse(entry.source, directory + "/Main.hx"));
			final program = new MacroExpandedProgram([TyperStage.typeResolvedModule(module, TyperIndex.build([module]))], false);
			final result = BackendRegistry.requireForTarget("cs-native")
				.emit(program, new BackendContext(directory + "/cs", null, "Main", true, true, new haxe.ds.StringMap<String>()));
			expect(run("gtimeout", ["30", "mono", result.entryPath]), entry.expected);
			Sys.println("CS_ENUM_SWITCH_RESULT:PASS " + entry.name);
		}
	}

	static function choiceProgram(body:String):String
		return "enum Choice { First(v:Int); Second(v:Int); } class Main { static function main() {" + body + "} }";

	/** Coverage must affect revisions and survive immutable copies and function-body adaptation. */
	static function checkCoverageCopies():Void {
		final position = HxPos.unknown();
		final value = TypedExpr.intLiteral(1, TyType.fromHintText("Int"), position);
		final region = TypedExpr.controlRegion([], TyType.fromHintText("Void"), position);
		final complete = TypedExpr.controlSwitch(value, [PWildcard], [region], TyType.fromHintText("Void"), position, [], true);
		final partial = TypedExpr.controlSwitch(value, [PWildcard], [region], TyType.fromHintText("Void"), position, [], false);
		if (!complete.withExpressions(complete.getExpressions()).withType(complete.getType()).getSwitchHasExhaustiveCoverage())
			throw "typed expression copy lost switch coverage";
		if (CompilerTypedTreeRevision.expression("probe", complete) == CompilerTypedTreeRevision.expression("probe", partial))
			throw "typed expression revision ignores switch coverage";
		final statement = TypedStmt.switchStmt(value, [PWildcard], [TypedStmt.block([], position)], position, [], true);
		if (!statement.withChildren(statement.getExpressions(), statement.getStatements()).withCatchUses([]).getSwitchHasExhaustiveCoverage())
			throw "typed statement copy lost switch coverage";
		final foreign = TypedExpr.boolLiteral(true, TyType.fromHintText("Bool"), position);
		if (complete.withExpressions([foreign, region]).getSwitchHasExhaustiveCoverage()
			|| statement.withChildren([foreign], statement.getStatements()).getSwitchHasExhaustiveCoverage())
			throw "changed input type retained foreign switch coverage";
		final statementRegion = TypedStatementControl.region([statement], null, position);
		if (!statementRegion.getExpressions()[0].getSwitchHasExhaustiveCoverage())
			throw "statement-to-control adaptation lost switch coverage";
		final projected = TypedBodySource.statement(statement);
		final copied = SourceFunctionBodyRewriter.body([projected], expression -> expression)[0];
		assertCoverage(copied);
		if (TypedBodyFingerprint.forStatements([copied]) == TypedBodyFingerprint.forStatements([SSwitch(EInt(1), [PWildcard], [SBlock([], position)],
			position)]))
			throw "statement fingerprint ignores switch coverage";
		final expression = TypedBodySource.expression(complete);
		final body = TypedControlStatements.functionBody(ELoweredControl(FunctionBody, "probe", [expression], position));
		assertCoverage(body[0]);
		if (TypedBodyFingerprint.forExpression(expression) == TypedBodyFingerprint.forExpression(TypedBodySource.expression(partial)))
			throw "lowered expression fingerprint ignores switch coverage";
	}

	static function assertCoverage(statement:HxStmt):Void {
		switch statement {
			case SSwitch(_, _, _, _, true):
			case _:
				throw "statement adaptation lost switch coverage";
		}
	}

	static function expect(actual:String, expected:String):Void {
		if (StringTools.trim(actual) != expected)
			throw "enum switch result differs: " + actual + " expected " + expected;
	}

	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final error = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw command + " failed: " + output + error;
		return output;
	}
}
