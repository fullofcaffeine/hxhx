/** Repeated statement conditions preserve effects, captures and their original jump destinations. */
class M14RepeatedConditionTest {
	static function main():Void {
		final cases = [
			{
				name: "do_continue",
				body: 'var value=0;var tests=0;do {try {value++;if(value==2)continue;if(value==4)break;Sys.println(value);} catch(e:Dynamic) {Sys.println("caught");}} while({tests++;value<8;});Sys.println(value);Sys.println(tests);',
				expected: "1\n3\n4\n3\n"
			},
			{
				name: "while_continue",
				body: 'var value=0;var tests=0;while({tests++;value<8;}) {value++;if(value==2)continue;if(value==4)break;Sys.println(value);}Sys.println(value);Sys.println(tests);',
				expected: "1\n3\n4\n4\n"
			},
			{
				name: "zero_once",
				body: 'var bodies=0;var tests=0;while({tests++;false;}) {bodies++;}do {bodies++;} while({tests++;false;});Sys.println(bodies);Sys.println(tests);',
				expected: "1\n2\n"
			},
			{
				name: "nested",
				body: 'var outer=0;var bodies=0;var tests=0;while(outer<3){outer++;var inner=0;do {inner++;bodies++;if(inner==1)continue;} while({tests++;inner<2;});}Sys.println(bodies);Sys.println(tests);',
				expected: "6\n6\n"
			},
			{
				name: "captures",
				body: 'var first:Void->Int=function():Int{return -1;};var second:Void->Int=first;var i=0;while({var local=i;var read=function():Int{local++;return local;};if(i==0)first=read;else if(i==1)second=read;i++;i<3;}) {}Sys.println(first());Sys.println(first());Sys.println(second());',
				expected: "1\n2\n2\n"
			},
			{
				name: "expression",
				body: 'var value=0;var tests=0;var result={do {value++;if(value==2)continue;} while({tests++;value<3;});value;};Sys.println(result);Sys.println(tests);',
				expected: "3\n3\n"
			},
			{
				name: "return",
				body: 'var call=function():Int{var n=0;while({n++;if(n==3)return n;true;}) {}return -1;};Sys.println(call());var once=function():Int{var n=0;do {n++;} while({return n;false;});return -1;};Sys.println(once());',
				expected: "3\n1\n"
			}
		];
		for (entry in cases)
			@:privateAccess M14NekoClosureControlTest.assertSource("repeated_" + entry.name, 'class Main {static function main():Void {' + entry.body + '}}',
				entry.expected);
		crossBackend('class Main {static function main():Void {' + cases[1].body + '}}', cases[1].expected);
	}

	/** Shared lowering must execute outside Neko and leave macro-visible source revisions intact. */
	static function crossBackend(source:String, expected:String):Void {
		final root = ".tmp/repeated_condition_native";
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final functions = typed.getTypedClasses()[0].getFunctions();
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		final program = new MacroExpandedProgram([typed], false);
		sys.FileSystem.createDirectory(root + "/src");
		sys.io.File.saveContent(root + "/src/Main.hx", source);
		final fixture = CppResolvedFixture.load({sourceRoot: root + "/src", mainModule: "Main", requiredModules: ["Sys"]});
		final cpp = backend.cpp.CppTargetCore.emit(new MacroExpandedProgram(fixture.modules, false),
			new backend.BackendContext(root + "/cpp", null, "Main", true, true, fixture.defines));
		if (!cpp.builtExecutable)
			throw "repeated condition requires a native executable";
		if (@:privateAccess M14NekoClosureControlTest.run(cpp.entryPath, []) != expected)
			throw "C++ repeated condition effects differ";
		final script = root + "/main.js";
		new backend.js.JsBackend().emit(program,
			new backend.BackendContext(root, script, "Main", true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"])));
		if (@:privateAccess M14NekoClosureControlTest.run("node", [script]) != expected)
			throw "JavaScript repeated condition effects differ";
		for (i in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[i]) != revisions[i])
				throw "repeated condition lowering changed the typed source";
		Sys.println("REPEATED_CONDITION_NATIVE:PASS targets=cpp,js source=unchanged");
	}
}
