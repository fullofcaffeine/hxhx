/** Selected static methods remain capture-free values through grouping and nested functions. */
class M14TypedCaptureStaticMethodTest {
	public static function run():Void {
		final source = 'class Main {
static function addOne(value:Int):Int{return value+1;}
static function main():Void {
var selected=((addOne));
var relay=function():Int{return ((addOne))(8);};
if(((addOne))(5)!=6 || selected(6)!=7 || relay()!=9)throw "static method selection";
}}';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final functions = typed.getTypedClasses()[0].getFunctions();
		final selected = functions[0].getDeclaration();
		final main = functions[1];
		var reads = 0;
		function expression(value:TypedExpr):Void {
			if (value.getTag() == NameRead && value.getTexts()[0] == "addOne") {
				check(value.getDeclaration() == selected, "grouped static method lost its selected declaration");
				reads++;
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
		for (value in main.getBody().getStatements())
			statement(value);
		check(reads == 3, "static method capture fixture lost a selected occurrence");
		Sys.println("STATIC_METHOD_DECLARATIONS:PASS");
		final before = CompilerTypedTreeRevision.functionBody(main);
		final plan = TypedCapturePlan.analyze(main);
		final scopes = plan.getFunctions();
		check(scopes.length == 2 && scopes[1].getCaptures().length == 0 && !scopes[1].capturesReceiver,
			"static method read invented a local or receiver capture");
		TypedCapturePlan.afterLowering(main, TypedControlLowering.functionBody(main));
		check(CompilerTypedTreeRevision.functionBody(main) == before, "static method capture analysis mutated source");
		// Removing the declaration must still reject a bare method value. Its
		// function type and spelling alone do not prove which method was selected.
		final statements = main.getBody().getStatements();
		final original = statements[0].getExpressions()[0];
		final unknown = TypedExpr.nameRead("addOne", original.getType(), original.getPosition());
		statements[0] = statements[0].withChildren([unknown], statements[0].getStatements());
		var rejected = false;
		try {
			TypedCapturePlan.analyze(main.withBody(new TypedFunctionBody(statements, main.getBody().getSourceFingerprint())));
		} catch (error:String) {
			rejected = error.indexOf("exact declaration for a bare method value") >= 0;
		}
		check(rejected, "capture analysis accepted a bare method without its declaration");
		JsRuntimeFixture.assertRuntime(typed, "Main", "");
		Sys.println("TYPED_CAPTURE_STATIC_METHOD:PASS");
	}

	static function check(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function main():Void
		run();
}
