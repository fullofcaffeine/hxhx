import backend.js.JsFunctionScope;
import backend.js.JsStmtEmitter;
import backend.js.JsWriter;

/** Local function hints preserve optionality through shared binding and ordinary JavaScript emission. */
class M14LocalFunctionSignatureIntegrationTest {
	static function typed(body:String):TypedFunction {
		final parsed = ParserStage.parse("class Main { static function run():Int { " + body + " } }", "Main.hx");
		return TyperStage.typeModule(parsed).getTypedClasses()[0].getFunctions()[0];
	}

	static function main():Void {
		callableContracts();
		for (entry in [
			{call: "choose()", expected: "7", omitted: true},
			{call: "choose(null)", expected: "7", omitted: false},
			{call: "choose(3)", expected: "3", omitted: false}
		]) {
			final body = typed("function choose(?value:Int):Int return value == null ? 7 : value; return " + entry.call + ";");
			final call = body.getBody().getStatements()[1].getExpressions()[0];
			final binding = call.getArgumentBinding();
			if (binding == null || binding.getSlots().length != 1 || binding.getSlots()[0].match(Omitted) != entry.omitted)
				throw "local optional call lost its omission binding";
			final projection = TypedBodySource.functionProjection(body);
			final writer = new JsWriter();
			final scope = new JsFunctionScope(new haxe.ds.StringMap<String>(), null, null, projection.getLocalCatalog());
			JsStmtEmitter.emitFunctionBody(writer, projection.getBody(), scope);
			final source = "function run(){\n" + writer.toString() + "\n}\nconsole.log(run());\n";
			final process = new sys.io.Process("node", ["-e", source]);
			final output = process.stdout.readAll().toString();
			final errors = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0 || StringTools.trim(output) != entry.expected)
				throw "local optional function execution differs: " + output + errors;
		}
		reject("function choose(?value:Int):Int return 7; return choose(\"bad\");", "String should be Int");
		reject("function choose(value:Null<Int>):Int return 7; return choose();", "Not enough arguments");
		final parsed = ParserStage.parse('class Main { static function run():String { function id(value:String, ?position:haxe.PosInfos) return position == null ? "missing" : value; return id("ok"); } }',
			"Main.hx");
		final positionBody = TyperStage.typeModule(parsed).getTypedClasses()[0].getFunctions()[0];
		final positionBinding = positionBody.getBody().getStatements()[1].getExpressions()[0].getArgumentBinding();
		if (positionBinding == null || !positionBinding.getSlots()[0].match(Supplied(0)) || !positionBinding.getSlots()[1].match(Omitted))
			throw "local PosInfos parameter lost its optional slot";
		Sys.println("LOCAL_FUNCTION_OPTIONAL_SIGNATURE:PASS");
	}

	/** Written defaults and rest parameters retain their call rules in the newer source-function representation. */
	static function callableContracts():Void {
		for (entry in [
			{
				declaration: "?value:Int",
				call: "choose()",
				optional: true,
				rest: false
			},
			{
				declaration: "value:Int=7",
				call: "choose()",
				optional: true,
				rest: false
			},
			{
				declaration: "...values:Int",
				call: "choose(1,2)",
				optional: false,
				rest: true
			}
		]) {
			final fn = typed("function choose(" + entry.declaration + "):Int return 7; return " + entry.call + ";");
			final source = fn.getBody().getStatements()[0].getExpressions()[0];
			final parameter = source.getType().getFunctionParameters()[0];
			if (parameter.isOptional != entry.optional
				|| parameter.isRest != entry.rest
				|| parameter.type.getSemanticKey() != "primitive:Int")
				throw "source function lost its callable parameter contract: " + entry.declaration;
			if (fn.getBody().getStatements()[1].getExpressions()[0].getArgumentBinding() == null)
				throw "source function call lost its validated argument binding";
		}
		reject("function choose(value:Null<Int>):Int return 7; return choose();", "Not enough arguments");
		reject("function choose(...values:Int):Int return 7; return choose('bad');", "String should be Int");
		Sys.println("SOURCE_FUNCTION_CALLABLE_CONTRACT:PASS");
	}

	static function reject(body:String, expected:String):Void {
		try {
			typed(body);
		} catch (error:TyperError) {
			if (Std.string(error).indexOf(expected) >= 0)
				return;
			throw error;
		}
		throw "invalid local-function call was accepted: " + body;
	}
}
