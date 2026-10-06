import backend.source.SourceNativeTarget;
import backend.source.SourceTargetCommon;

/** Execute projected sequence bodies through source-target expression and statement renderers. */
class M14SourceSequenceObserver {
	/** Rewriters and dependency scans must see both sides of the new expression node. */
	public static function checkWalkers():Void {
		final source = HxExpr.EDiscardThen(EIdent("left"), EIdent("right"));
		final references = new Map<String, Bool>();
		@:privateAccess SourceTargetCommon.collectJavaEntryBodyFunctionRefsInExpr(source, references, false);
		if (!references.exists("left") || !references.exists("right"))
			throw "Java references lost sequence children";
		final calls = new Array<{name:String, arity:Int}>();
		@:privateAccess SourceTargetCommon.collectJavaEntryBodyDirectCallsInExpr(EDiscardThen(ECall(EIdent("left"), []), ECall(EIdent("right"), [])), calls);
		if (calls.length != 2 || calls[0].name != "left" || calls[1].name != "right" || calls[0].arity != 0 || calls[1].arity != 0)
			throw "Java calls lost sequence children";
		final captures = @:privateAccess SourceTargetCommon.phpLambdaUsedCaptures(source, []);
		if (captures.join(",") != "left,right")
			throw "PHP captures lost sequence children";
		final assignments = HxExpr.EDiscardThen(EBinop("=", EIdent("left"), EInt(1)), EBinop("=", EIdent("right"), EInt(2)));
		final assigned = @:privateAccess SourceTargetCommon.phpLambdaAssignedCaptures(assignments, []);
		if (assigned.join(",") != "left,right")
			throw "PHP assigned captures lost sequence children";
		final members = new Map<String, Bool>();
		members.set("left", true);
		members.set("right", true);
		final python = @:privateAccess SourceTargetCommon.pythonRewriteSameClassMemberExpr(source, members, new Map(), []);
		final php = @:privateAccess SourceTargetCommon.phpRewriteSameClassMemberExpr(source, members, new Map(), new Map(), "Owner", []);
		for (rewritten in [python, php])
			if (!rewritten.match(EDiscardThen(EField(EThis, "left"), EField(EThis, "right"))))
				throw "instance member rewrite lost sequence children";
		final cs = @:privateAccess SourceTargetCommon.csRewriteSameClassStaticMemberExpr(source, members, "Owner", []);
		if (!cs.match(EDiscardThen(EField(EIdent("Owner"), "left"), EField(EIdent("Owner"), "right"))))
			throw "C# static member rewrite lost sequence children";
		final renamed = new haxe.ds.StringMap<String>();
		renamed.set("left", "first");
		renamed.set("right", "second");
		final phpNames = @:privateAccess SourceTargetCommon.phpRenameScopedLocalExpr(source, renamed, new haxe.ds.StringMap<Int>(), false);
		if (!phpNames.match(EDiscardThen(EIdent("first"), EIdent("second"))))
			throw "PHP local rename lost sequence children";
	}

	static function main():Void {
		checkWalkers();
		final parsed = ParserStage.parse("class Main { static function run(step:()->Void):Int return { step(); step(); 7; }; }", "Main.hx");
		final module = new ResolvedModule("Main", "Main.hx", parsed);
		final body = TyperStage.typeResolvedModule(module, TyperIndex.build([module])).getTypedClasses()[0].getFunctions()[0];
		final projection = TypedBodySource.functionProjection(body);
		observe(projection, HxFunctionArg.getName(HxFunctionDecl.getArgs(projection.getDeclaration())[0]));
		Sys.println("SOURCE_SEQUENCE:PASS");
	}

	/** Render the complete lowered body so result locals and discarded calls share their real scope. */
	public static function observe(projection:TypedBackendFunctionProjection, parameter:String):Void {
		final root = ".tmp/sequence_source_" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		final quoteSource = HxExpr.ESourceGroup([EInt(1), EInt(2)], HxPos.unknown());
		final pythonQuote = @:privateAccess SourceTargetCommon.pythonMacroExpr(quoteSource, []);
		check(root
			+ "/quote.py", "python3", [],
			"from types import SimpleNamespace as hxhx_anon\nquoted="
			+ pythonQuote
			+
			"\nitems=quoted.expr.__hx_params[0]\nprint(quoted.expr.__hx_ctor+':'+str(len(items))+':'+items[0].expr.__hx_params[0].__hx_params[0]+':'+items[1].expr.__hx_params[0].__hx_params[0])\n",
			"EBlock:2:1:2");
		final phpQuote = @:privateAccess SourceTargetCommon.phpMacroExpr(quoteSource, []);
		check(root
			+ "/quote.php", "php", [],
			"<?php $quoted="
			+ phpQuote
			+
			"; $items=$quoted->expr->__hx_params[0]; echo $quoted->expr->__hx_ctor,':',count($items),':',$items[0]->expr->__hx_params[0]->__hx_params[0],':',$items[1]->expr->__hx_params[0]->__hx_params[0],\"\\n\";",
			"EBlock:2:1:2");
		final python = @:privateAccess SourceTargetCommon.renderStmts(Python, projection.getBody(), " ").join("\n");
		check(root
			+ "/sequence.py", "python3", [],
			"state=[0,False]\ndef "
			+ parameter
			+ "():\n state[0]+=1\n if state[1]: raise Exception('stop')\ndef run():\n"
			+ python
			+ "\nresult=run()\nprint(str(result)+':'+str(state[0]))\nstate[:]=[0,True]\ntry:\n run()"
			+ "\n print('unexpected')\nexcept Exception as e:\n print(str(e)+':'+str(state[0]))\n");
		final lua = @:privateAccess SourceTargetCommon.renderStmts(Lua, projection.getBody(), " ").join("\n");
		check(root
			+ "/sequence.lua", "lua", [],
			"local n=0; local stop=false; local function "
			+ parameter
			+ "() n=n+1; if stop then error('stop',0) end end\nlocal function run()\n"
			+ lua
			+ "\nend\nlocal result=run()\nprint(result..':'..n)\nn=0;stop=true;local ok,err=pcall(run)"
			+ "\nif ok then error('unexpected') end\nprint(err..':'..n)\n");
		final javaBody = @:privateAccess SourceTargetCommon.renderStmts(Java, projection.getBody(), "").join("\n");
		sys.io.File.saveContent(root
			+ "/Sequence.java",
			"class Sequence { static int n=0; static boolean stop=false; static void "
			+ parameter
			+ "(){++n;if(stop)throw new RuntimeException(\"stop\");} static int run(){"
			+ javaBody
			+ "} public static void main(String[] args){System.out.println(run()+\":\"+n);n=0;stop=true;try{run();throw new Error(\"unexpected\");}"
			+ "catch(RuntimeException e){System.out.println(e.getMessage()+\":\"+n);}}}\n");
		run("javac", [root + "/Sequence.java"]);
		requireOutput(run("java", ["-cp", root, "Sequence"]));
		final csBody = @:privateAccess SourceTargetCommon.renderStmts(Cs, projection.getBody(), "").join("\n");
		sys.io.File.saveContent(root
			+ "/Sequence.cs",
			"class Sequence { static int n=0; static bool stop=false; static void "
			+ parameter
			+ "(){++n;if(stop)throw new System.Exception(\"stop\");} static int run(){"
			+ csBody
			+ "} static void Main(){System.Console.WriteLine(run()+\":\"+n);n=0;stop=true;try{run();System.Console.WriteLine(\"unexpected\");}"
			+ "catch(System.Exception e){System.Console.WriteLine(e.Message+\":\"+n);}}}\n");
		run("mcs", ["-out:" + root + "/Sequence.exe", root + "/Sequence.cs"]);
		requireOutput(run("mono", [root + "/Sequence.exe"]));
	}

	static function check(path:String, command:String, arguments:Array<String>, source:String, expected:String = "7:2\nstop:1"):Void {
		sys.io.File.saveContent(path, source);
		final output = run(command, arguments.concat([path]));
		if (StringTools.trim(output) != expected)
			throw command + " sequence differs: " + output;
	}

	static function requireOutput(output:String):Void {
		if (StringTools.trim(output) != "7:2\nstop:1")
			throw "source sequence differs: " + output;
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
}
