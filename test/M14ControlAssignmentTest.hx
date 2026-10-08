/**
	Field and array assignments preserve their distinct upstream control-value evaluation order.
	One real provider graph per target serves all cases, whose separate functions
	retain independent locals and return destinations. Both Neko layouts include catches.
 */
class M14ControlAssignmentTest {
	static function main():Void {
		final cases = [
			{
				name: 'field',
				body: 'var box={value:0};box.value=try {Sys.println("rhs");7;}catch(e:Dynamic){9;};Sys.println(box.value);',
				expected: 'rhs\n7\n'
			},
			{
				name: 'receiver',
				body: 'var first={value:0};var second={value:0};var selected=first;selected.value={selected=second;7;};Sys.println(first.value);Sys.println(second.value);',
				expected: '0\n7\n'
			},
			{
				name: 'dynamic_receiver',
				body: 'var first={value:0};var second={value:0};var selected:Dynamic=first;selected.value={selected=second;7;};Sys.println(first.value);Sys.println(second.value);',
				expected: '0\n7\n'
			},
			{
				name: 'array',
				body: 'var first=[0,0];var second=[0,0];var selected=first;var i=0;selected[i]={selected=second;i=1;7;};Sys.println(first[0]);Sys.println(first[1]);Sys.println(second[0]);',
				expected: '7\n0\n0\n'
			},
			{
				name: 'throw',
				body: 'var box={value:0};try {receiver(box).value={Sys.println("rhs");throw "stop";7;};}catch(e:Dynamic){Sys.println("caught");}Sys.println(box.value);',
				expected: 'rhs\ncaught\n0\n'
			},
			{
				name: 'receiver_call',
				body: 'var box={value:0};receiver(box).value={Sys.println("rhs");7;};Sys.println(box.value);',
				expected: 'rhs\nreceiver\n7\n'
			},
			{
				name: 'address_group',
				body: 'var box={value:0};({Sys.println("address");box;}).value={Sys.println("rhs");7;};Sys.println(box.value);',
				expected: 'address\nrhs\n7\n'
			},
			{
				name: 'array_calls',
				body: 'var items=[0];arrayReceiver(items)[arrayIndex()]={Sys.println("rhs");7;};Sys.println(items[0]);',
				expected: 'array\nindex\nrhs\n7\n'
			},
			{
				name: 'array_throw',
				body: 'var items=[0];try{arrayReceiver(items)[arrayIndex()]={Sys.println("rhs");throw "stop";7;};}catch(e:Dynamic){Sys.println("caught");}Sys.println(items[0]);',
				expected: 'array\nindex\nrhs\ncaught\n0\n'
			},
			{
				name: 'plain_calls',
				body: 'var box={value:0};receiver(box).value=right();Sys.println(box.value);',
				expected: 'receiver\nrhs\n7\n'
			},
			{
				name: 'return',
				body: 'var box={value:0};receiver(box).value={Sys.println("rhs");return;7;};Sys.println("bad");',
				expected: 'rhs\n'
			}
		];
		final methods = 'static function receiver(value:{value:Int}):{value:Int}{Sys.println("receiver");return value;}'
			+ 'static function arrayReceiver(value:Array<Int>):Array<Int>{Sys.println("array");return value;}'
			+ 'static function arrayIndex():Int{Sys.println("index");return 0;}'
			+ 'static function right():Int{Sys.println("rhs");return 7;}';
		final root = '.tmp/control_assignment_full';
		sys.FileSystem.createDirectory(root);
		// Resolve each target's real providers once. Each original case remains a
		// separate function, so its locals and return destination stay independent.
		final caseFunctions = [
			for (i in 0...cases.length)
				'static function case' + i + '():Void{' + cases[i].body + '}'
		];
		final calls = [for (i in 0...cases.length) 'case' + i + '();'];
		final source = 'class Main{' + methods + caseFunctions.join('') + 'static function main():Void{' + calls.join('') + '}}';
		final expected = cases.map(entry -> entry.expected).join('');
		sys.io.File.saveContent(root + '/Main.hx', source);
		sys.io.File.saveContent(root + '/expected.stdout', expected);
		if (Sys.command('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '-neko', root + '/upstream.n']) != 0)
			throw 'upstream assignment compilation failed';
		assertOutput('neko', [root + '/upstream.n'], expected);
		Sys.println('UPSTREAM_CONTROL_ASSIGNMENT:PASS cases=' + cases.length);

		final sources = [{path: 'Main.hx', source: source}];
		final js = JsSourceProgramFixture.build({sources: sources, requiredModules: ['Array', 'Sys', 'haxe.Exception']});
		final jsFunctions = authoredFunctions(js, cases.length + 5);
		final jsRevisions = jsFunctions.map(CompilerTypedTreeRevision.functionBody);
		final jsContext = new backend.BackendContext(root, root + '/local.js', 'Main', true, false, HxDefineMap.fromRawDefines(['js=1', 'js-es=5']));
		new backend.js.JsBackend().emit(js, jsContext);
		assertOutput('node', [root + '/local.js'], expected);
		assertSourceUnchanged(jsFunctions, jsRevisions);
		Sys.println('JS_CONTROL_ASSIGNMENT:PASS cases=' + cases.length);

		assertNeko({
			sources: sources,
			root: root,
			expected: expected,
			caseCount: cases.length
		});
	}

	/** Execute the same complete source in both Neko layouts with real exception providers. */
	static function assertNeko(input:{
		sources:Array<{path:String, source:String}>,
		root:String,
		expected:String,
		caseCount:Int
	}):Void {
		final neko = NekoSourceProgramFixture.build(input.sources);
		for (required in ['Array', 'Sys', 'haxe.Exception']) {
			final providers = [
				for (module in neko.getTypedModules())
					if (module.getSourceOrigin().sourceModulePath == required) module
			];
			if (providers.length != 1 || !sys.FileSystem.exists(providers[0].getParsed().getFilePath()))
				throw 'assignment fixture omitted a real Neko provider: ' + required;
			if (required == 'haxe.Exception'
				&& !StringTools.endsWith(providers[0].getParsed().getFilePath().split('\\').join('/'), '/neko/_std/haxe/Exception.hx'))
				throw 'assignment fixture selected the wrong Neko exception provider';
		}
		final nekoFunctions = authoredFunctions(neko, input.caseCount + 5);
		final nekoRevisions = nekoFunctions.map(CompilerTypedTreeRevision.functionBody);
		final root = input.root;
		final expected = input.expected;
		final nekoContext = new backend.BackendContext(root, root + '/local.n', 'Main', true, false, HxDefineMap.fromRawDefines(['neko=1']));
		final result = backend.vm.NekoTargetCore.emit(neko, nekoContext);
		assertOutput('neko', [result.entryPath], expected);
		assertSourceUnchanged(nekoFunctions, nekoRevisions);
		Sys.println('NEKO_CONTROL_ASSIGNMENT:PASS layout=split cases=' + input.caseCount);
		sys.io.File.saveContent(root + '/single.neko', @:privateAccess backend.vm.NekoTargetCore.renderProgram(neko, nekoContext));
		if (Sys.command('nekoc', [root + '/single.neko']) != 0)
			throw 'generated single-file assignment compilation failed';
		assertOutput('neko', [root + '/single.n'], expected);
		assertSourceUnchanged(nekoFunctions, nekoRevisions);
		Sys.println('NEKO_CONTROL_ASSIGNMENT:PASS layout=single cases=' + input.caseCount);
	}

	/** Check every authored function's lowering identities before either backend executes it. */
	static function authoredFunctions(program:MacroExpandedProgram, expectedCount:Int):Array<TypedFunction> {
		final functions = [
			for (module in program.getTypedModules())
				for (owner in module.getTypedClasses())
					if (owner.getSemanticInfo().getIdentity().getCanonicalName() == 'Main')
						for (fn in owner.getFunctions())
							fn
		];
		if (functions.length != expectedCount)
			throw 'assignment fixture lost an authored function';
		for (fn in functions) {
			final revision = CompilerTypedTreeRevision.functionBody(fn);
			final lowered = TypedControlLowering.functionBody(fn);
			if (CompilerTypedTreeRevision.functionBody(lowered) != CompilerTypedTreeRevision.functionBody(TypedControlLowering.functionBody(lowered)))
				throw 'repeated assignment lowering changed its identities';
			if (CompilerTypedTreeRevision.functionBody(fn) != revision)
				throw 'assignment lowering changed typed source';
		}
		return functions;
	}

	/** Compare a real target process with the independently authored output. */
	static function assertOutput(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(Sys.systemName() == 'Mac' ? 'gtimeout' : 'timeout', ['30', command].concat(arguments));
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected)
			throw 'assignment output differs: ' + output + errors;
	}

	/** Derived execution plans must not rewrite the typed source used by macros and revision checks. */
	static function assertSourceUnchanged(functions:Array<TypedFunction>, revisions:Array<String>):Void {
		for (index in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[index]) != revisions[index])
				throw 'assignment lowering changed typed source';
	}
}
