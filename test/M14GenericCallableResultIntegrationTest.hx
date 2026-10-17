import backend.js.JsFunctionScope;
import backend.js.JsStmtEmitter;
import backend.js.JsWriter;

/** Generic method results keep callback parameter contracts after type substitution. */
class M14GenericCallableResultIntegrationTest {
	static function main():Void {
		final source = "extern class Factory { static function optional<T>(value:T):(?item:T)->T; static function rest<T>(value:T):(...items:T)->T; static function required<T>(value:T):(item:T)->T; }";
		final module = new ResolvedModule("Factory", "Factory.hx", ParserStage.parse(source, "Factory.hx"));
		final index = TyperIndex.build([module]);
		final owner = index.getByFullName("Factory");
		final intType = TyType.fromHintText("Int");
		for (name in ["optional", "rest", "required"]) {
			final signature = owner.staticMethod(name);
			final declaration = owner.declarationForSignature(signature);
			final result = TyMethodGenericBinding.specializeResult(declaration, signature, [intType], index);
			final parameters = result.getFunctionParameters();
			if (parameters.length != 1
				|| parameters[0].type.getSemanticKey() != intType.getSemanticKey()
				|| result.getFunctionReturn().getSemanticKey() != intType.getSemanticKey())
				throw name + ": generic callback types were not substituted";
			if (parameters[0].isOptional != (name == "optional") || parameters[0].isRest != (name == "rest"))
				throw name + ": generic substitution erased optional/rest parameter facts";
			if (parameters[0].name != (name == "rest" ? "items" : "item"))
				throw name + ": generic substitution erased the parameter name";
			final callable = TyCallableSignature.fromFunctionValue(result);
			final omission = TyCallValidation.validate(callable, [], [], Unchecked);
			switch (omission) {
				case Aligned(_) if (name != "required"):
				case Rejected(MissingRequired(0)) if (name == "required"):
				case _:
					throw name + ": unexpected omission decision " + omission;
			}
			if (!signature.getReturnType().getFunctionParameters()[0].type.isTypeParameter())
				throw name + ": specialization mutated the indexed generic declaration";
		}
		checkReturnedCallbackCall();
		checkRestMethodSelection();
		Sys.println("GENERIC_CALLABLE_RESULT:PASS");
	}

	/** Each rest operand supplies an element, including evidence for a method generic. */
	static function checkRestMethodSelection():Void {
		final source = "class Main { static function count(prefix:Int, ...values:Int):Int return prefix + values.length; "
			+ "static function first<T>(...values:T):T return values[0]; static function main():Void { "
			+ "var empty=count(5); var many=count(5,7,8); var picked=first(11,12); "
			+ "if (empty!=5 || many!=7 || picked!=11) throw 'rest mismatch'; } }";
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final index = TyperIndex.build([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index);
		final main = typed.getTypedClasses()[0].getFunctions()[2];
		for (local in main.getEnvironment().getLocals())
			if (local.getType().getSemanticKey() != TyType.fromHintText("Int").getSemanticKey())
				throw "rest call did not infer Int for " + local.getName();
		for (statement in main.getBody().getStatements())
			if (statement.getTag() == TypedStmt.TypedStmtTag.Var) {
				final call = statement.getExpressions()[0];
				if (call.getDeclaration() == null || call.getArgumentBinding() != null)
					throw "rest method call lost declaration-based selection";
			}
		final output = Sys.getCwd() + "/.tmp/m14_rest_method_selection";
		final artifact = new backend.js.JsTargetCore().emit(new MacroExpandedProgram([typed], false),
			new backend.BackendContext(output, output + "/main.js", "Main", true, false, new haxe.ds.StringMap<String>()));
		final process = new sys.io.Process("node", [artifact.entryPath]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != "")
			throw "generated rest method calls failed: " + stdout + stderr;
		final invalidSource = "class Invalid { static function first<T>(...values:T):T return values[0]; "
			+ "static function run():Void { var bad=first(1,2,'x'); } static function main():Void {run();} }";
		final invalidRoot = ".tmp/m14_rest_method_rejection";
		sys.FileSystem.createDirectory(invalidRoot);
		sys.io.File.saveContent(invalidRoot + "/Invalid.hx", invalidSource);
		final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", invalidRoot, "-main", "Invalid", "--no-output"]);
		upstream.stdout.readAll();
		final upstreamErrors = upstream.stderr.readAll().toString();
		final upstreamCode = upstream.exitCode();
		upstream.close();
		if (upstreamCode == 0 || upstreamErrors.indexOf("String should be Int") < 0)
			throw "upstream did not reject the conflicting rest element: " + upstreamErrors;
		final invalid = new ResolvedModule("Invalid", "Invalid.hx", ParserStage.parse(invalidSource, "Invalid.hx"));
		var rejected = false;
		try
			TyperStage.typeResolvedModule(invalid, TyperIndex.build([invalid]))
		catch (error:TyperError) {
			if (error.message.indexOf("No compatible method signature for first") < 0)
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "a conflicting later rest operand was accepted";
	}

	/** An omitted callback operand remains legal after passing through a generic method. */
	static function checkReturnedCallbackCall():Void {
		final factory = new ResolvedModule("Factory", "Factory.hx",
			ParserStage.parse("class Factory { public static function keep<T>(value:T, callback:(?T)->T):(?T)->T { return callback; } }", "Factory.hx"));
		final main = new ResolvedModule("Main", "Main.hx",
			ParserStage.parse("class Main { static function run(callback:(?Int)->Int):Int { var selected = Factory.keep(7, callback); return selected(); } }",
				"Main.hx"));
		final index = TyperIndex.build([factory, main]);
		final factoryFunction = TyperStage.typeResolvedModule(factory, index).getTypedClasses()[0].getFunctions()[0];
		final mainFunction = TyperStage.typeResolvedModule(main, index).getTypedClasses()[0].getFunctions()[0];
		final selectedType = mainFunction.getEnvironment().getLocals()[0].getType();
		if (!selectedType.getFunctionParameters()[0].isOptional)
			throw "returned callback lost optionality before call validation";
		final targetNames = new haxe.ds.StringMap<String>();
		targetNames.set("Factory", "Factory");
		final source = "const Factory = {keep: function(value,callback){" + emitBody(factoryFunction, targetNames) + "}}; function run(callback){"
			+ emitBody(mainFunction, targetNames) + "} console.log(run(value => value == null ? 9 : value));";
		final process = new sys.io.Process("node", ["-e", source]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != "9\n")
			throw "generic returned callback execution differs: " + output + errors;
	}

	/** Render the shared typed body; the surrounding JavaScript only supplies test entry points. */
	static function emitBody(fn:TypedFunction, targetNames:haxe.ds.StringMap<String>):String {
		final projection = TypedBodySource.functionProjection(fn);
		final writer = new JsWriter();
		final scope = new JsFunctionScope(targetNames, null, null, projection.getLocalCatalog());
		JsStmtEmitter.emitFunctionBody(writer, projection.getBody(), scope);
		return writer.toString();
	}
}
