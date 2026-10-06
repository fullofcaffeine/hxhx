import backend.js.JsExprEmitter;
import backend.js.JsFunctionScope;
import HxExpr;

/** Discarded expressions run in order without becoming arguments to synthetic functions. */
class M14SequenceExpressionIntegrationTest {
	static function main():Void {
		walkers();
		M14SourceSequenceObserver.checkWalkers();
		final parsed = ParserStage.parse("class Main { static function run(step:()->Void):Int return { step(); step(); 7; }; }", "Main.hx");
		final module = new ResolvedModule("Main", "Main.hx", parsed);
		final functionBody = TyperStage.typeResolvedModule(module, TyperIndex.build([module])).getTypedClasses()[0].getFunctions()[0];
		final value = functionBody.getBody().getStatements()[0].getExpressions()[0];
		if (!value.getTag().match(Block) || value.getType().getDisplay() != "Int")
			throw "sequence did not retain its typed children and final result";
		final projection = TypedBodySource.functionProjection(functionBody);
		final scope = new JsFunctionScope(new haxe.ds.StringMap<String>(), null, null, projection.getLocalCatalog());
		final name = scope.declareLocal(HxFunctionArg.getName(HxFunctionDecl.getArgs(projection.getDeclaration())[0]));
		final expression = switch (projection.getBody()[0]) {
			case SReturn(result, _): result;
			case _: throw "missing projected sequence";
		};
		final generated = JsExprEmitter.emit(expression, scope.exprScope());
		observe("let n=0;const " + name + "=()=>{n++;};const result=" + generated + ";console.log(result+':'+n);", "7:2");
		observe("let n=0;const "
			+ name
			+ "=()=>{n++;throw new Error('stop');};try{"
			+ generated
			+ ";console.log('unexpected');}catch(e){console.log(e.message+':'+n);}",
			"stop:1");
		observeOcaml(expression, projection, name);
		observeCpp(expression, name);
		observeNeko(expression, name);
		Sys.println("SEQUENCE_EXPRESSION:PASS");
	}

	/** Native Neko blocks retain the last value and stop evaluating after an exception. */
	static function observeNeko(expression:HxExpr, parameter:String):Void {
		final locals = new haxe.ds.StringMap<Bool>();
		locals.set(parameter, true);
		final context:backend.vm.NekoEmitContext = {
			classes: new haxe.ds.StringMap(),
			typedProgram: null,
			currentExecutable: null,
			captureStorage: null,
			abstractHelpers: [],
			abstractHelperIds: new haxe.ds.StringMap(),
			directAbstractReceiver: false,
			selfName: null,
			currentClass: null,
			symbolTable: null,
			packFunctionArguments: false,
			locals: locals,
			insideTry: false,
			breakFlag: null
		};
		final cls = HxModuleDecl.getClasses(ParserStage.parse("class Dependency {}", "Dependency.hx").getDecl())[0];
		context.classes.set("Dependency", {fullName: "Dependency", shortName: "Dependency", cls: cls});
		for (node in [
			EDiscardThen(ENew("Dependency", []), EInt(1)),
			EDiscardThen(EInt(1), ENew("Dependency", []))
		]) {
			var found = 0;
			@:privateAccess backend.vm.NekoTargetCore.collectExprRefs(context, node, info -> found++, (info, fn) -> {});
			if (found != 1)
				throw "Neko dependency traversal skipped a sequence child";
		}
		final generated = @:privateAccess backend.vm.NekoTargetCore.renderExpr(context, expression);
		final quoted = backend.vm.NekoMacroExprLowering.render(ESourceGroup([EInt(1), EInt(2)], HxPos.unknown()), [],
			_ -> throw "sequence quotation used fallback");
		final root = ".tmp/sequence_neko_" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		final source = "var state=$new(null); state.n=0; var "
			+ parameter
			+ "=function(){ state.n=state.n+1; }; var result="
			+ generated
			+ "; $print(result,\":\",state.n,\"\\n\"); state.n=0; "
			+ parameter
			+ "=function(){ state.n=state.n+1; $throw(\"stop\"); }; try { "
			+ generated
			+ "; $print(\"unexpected\\n\"); } catch e { $print(e,\":\",state.n,\"\\n\"); } var quoted="
			+ quoted
			+ "; var items=quoted.expr.__hx_params[0]; $print(quoted.expr.__hx_ctor,\":\",$asize(items),\":\","
			+ "items[0].expr.__hx_params[0].__hx_params[0],\":\",items[1].expr.__hx_params[0].__hx_params[0],\"\\n\");";
		sys.io.File.saveContent(root + "/sequence.neko", source);
		run("nekoc", [root + "/sequence.neko"]);
		final output = run("neko", [root + "/sequence.n"]);
		if (StringTools.trim(output) != "7:2\nstop:1\nEBlock:2:1:2")
			throw "native Neko sequence differs: " + output;
	}

	/** Shared transforms must visit both children in order and keep unsupported nodes visible. */
	static function walkers():Void {
		for (name in ["table", "__hxhx_lambda_seq_7"]) {
			final setEntry = ECall(EField(EIdent(name), "set"), [EString("key"), EString("value")]);
			final init = ECall(ELambda([name], EDiscardThen(setEntry, EIdent(name))), [ENew("haxe.ds.StringMap", [])]);
			final plan = @:privateAccess backend.cpp.CppTargetCore.parseStructuredStringMapInit(init);
			if (plan == null || plan.local != name || plan.keys.length != 1 || !plan.keys[0].match(EString("key")) || !plan.values[0].match(EString("value")))
				throw "C++ map initialization lost its exact binder or sequence entry";
		}
		for (name in ["eq", "assert", "push"])
			if (@:privateAccess backend.cpp.CppTargetCore.exprReturnsVoid(ECall(EIdent(name), [])))
				throw "C++ inferred Void from a function name alone";
		final visited = new Array<Int>();
		final source:HxExpr = EDiscardThen(EInt(1), EInt(2));
		final rewritten = backend.source.SourceFunctionBodyRewriter.expressionWithOriginal(source, (original, rebuilt) -> switch (original) {
			case EInt(value):
				visited.push(value);
				EInt(value + 10);
			case _: rebuilt;
		});
		if (visited.join(",") != "1,2" || !rewritten.match(EDiscardThen(EInt(11), EInt(12))))
			throw "source rewrite skipped or reordered sequence children";
		for (node in [
			EDiscardThen(EUnsupported("first"), EInt(1)),
			EDiscardThen(EInt(1), EUnsupported("second"))
		])
			if (!(@:privateAccess ParserStageScanHelpers.hasUnsupportedExpr(node)))
				throw "sequence hid unsupported source";
		for (node in [
			EDiscardThen(ECall(EIdent("callback"), []), EInt(1)),
			EDiscardThen(EInt(1), ECall(EIdent("callback"), []))
		])
			if (!backend.cpp.CppLocalCallScanner.stmtListCallsLocal([SReturn(node, HxPos.unknown())], "callback"))
				throw "C++ call scan skipped a sequence child";
	}

	/** The native comma operator discards even a Void first child and stops when it throws. */
	static function observeCpp(expression:HxExpr, parameter:String):Void {
		final generated = @:privateAccess backend.cpp.CppTargetCore.renderExpr(expression);
		final quoted = backend.cpp.CppMacroExpr.macroExpr(ESourceGroup([EInt(1), EInt(2)], HxPos.unknown()), []);
		final ordinaryLambda = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(ELambda(["__hxhx_lambda_seq_0"], EIdent("__hxhx_lambda_seq_0")),
			[ECall(EIdent("eq"), [])]));
		final resultType = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(expression);
		if (resultType != "int")
			throw "C++ sequence lost its continuation type: " + resultType;
		final root = ".tmp/sequence_cpp_" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		final source = "#include <cstdio>\n#include <stdexcept>\n#include <memory>\n#include <vector>\n#include <string>\n#include <sstream>\n"
			+ backend.cpp.CppMacroExpr.runtimePreludeLines().join("\n")
			+ "\nint main(){ { int n=0; auto "
			+ parameter
			+ "=[&](){++n;};auto result="
			+ generated
			+ ";std::printf(\"%d:%d\\n\",result,n); } {int n=0;auto "
			+ parameter
			+ "=[&](){++n;throw std::runtime_error(\"stop\");};try{(void)("
			+ generated
			+ ");std::puts(\"unexpected\");}catch(const std::runtime_error& e){std::printf(\"%s:%d\\n\",e.what(),n);}} auto quoted="
			+ quoted
			+ ";std::puts(__hxhx_macro_to_string(quoted).c_str());auto eq=[](){return 9;};auto ordinary="
			+ ordinaryLambda
			+ ";std::printf(\"%d\\n\",ordinary);}\n";
		sys.io.File.saveContent(root + "/sequence.cpp", source);
		run("c++", ["-std=c++17", "-o", root + "/sequence.exe", root + "/sequence.cpp"]);
		final output = run(root + "/sequence.exe", []);
		if (StringTools.trim(output) != "7:2\nstop:1\nEBlock(EConst(CInt(1)),EConst(CInt(2)))\n9")
			throw "native C++ sequence differs: " + output;
	}

	/** Compile the projected authored body and observe both normal and exceptional native execution. */
	static function observeOcaml(expression:HxExpr, projection:TypedBackendFunctionProjection, parameterName:String):Void {
		final names = new backend.ocaml.Stage3OcamlLocalNames(projection.getLocalCatalog(), false, name -> @:privateAccess EmitterStage.ocamlValueIdent(name));
		@:privateAccess EmitterStage.currentFunctionLocalOcamlNames = names;
		final generated = @:privateAccess EmitterStage.exprToOcaml(expression);
		@:privateAccess EmitterStage.currentFunctionLocalOcamlNames = null;
		final parameter = names.targetName(parameterName);
		final root = ".tmp/sequence_expression_" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		final source = "let () = let n = ref 0 in let "
			+ parameter
			+ " () = incr n in let result = "
			+ generated
			+ " in Printf.printf \"%d:%d\\n\" result !n\n"
			+ "let () = let n = ref 0 in let "
			+ parameter
			+ " () = incr n; failwith \"stop\" in try ignore ("
			+ generated
			+ "); print_endline \"unexpected\" with Failure text -> Printf.printf \"%s:%d\\n\" text !n\n";
		sys.io.File.saveContent(root + "/sequence.ml", source);
		run("ocamlc", ["-o", root + "/sequence.exe", root + "/sequence.ml"]);
		final output = run(root + "/sequence.exe", []);
		if (StringTools.trim(output) != "7:2\nstop:1")
			throw "native OCaml sequence differs: " + output;
	}

	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw command + " failed: " + output + errors;
		return output;
	}

	static function observe(source:String, expected:String):Void {
		final process = new sys.io.Process("node", ["-e", source]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || StringTools.trim(output) != expected)
			throw "sequence observation differs: " + output + errors;
	}
}
