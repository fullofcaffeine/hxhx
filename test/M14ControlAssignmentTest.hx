/** Field and array assignments preserve their distinct upstream control-value evaluation order. */
class M14ControlAssignmentTest {
	static function main():Void {
		final cases = [
			{
				name: 'field',
				body: 'var box={value:0};box.value=try {Sys.println("rhs");7;}catch(e:Dynamic){9;};Sys.println(box.value);',
				expected: 'rhs\n7\n',
				catches: true
			},
			{
				name: 'receiver',
				body: 'var first={value:0};var second={value:0};var selected=first;selected.value={selected=second;7;};Sys.println(first.value);Sys.println(second.value);',
				expected: '0\n7\n',
				catches: false
			},
			{
				name: 'dynamic_receiver',
				body: 'var first={value:0};var second={value:0};var selected:Dynamic=first;selected.value={selected=second;7;};Sys.println(first.value);Sys.println(second.value);',
				expected: '0\n7\n',
				catches: false
			},
			{
				name: 'array',
				body: 'var first=[0,0];var second=[0,0];var selected=first;var i=0;selected[i]={selected=second;i=1;7;};Sys.println(first[0]);Sys.println(first[1]);Sys.println(second[0]);',
				expected: '7\n0\n0\n',
				catches: false
			},
			{
				name: 'throw',
				body: 'var box={value:0};try {receiver(box).value={Sys.println("rhs");throw "stop";7;};}catch(e:Dynamic){Sys.println("caught");}Sys.println(box.value);',
				expected: 'rhs\ncaught\n0\n',
				catches: true
			},
			{
				name: 'receiver_call',
				body: 'var box={value:0};receiver(box).value={Sys.println("rhs");7;};Sys.println(box.value);',
				expected: 'rhs\nreceiver\n7\n',
				catches: false
			},
			{
				name: 'address_group',
				body: 'var box={value:0};({Sys.println("address");box;}).value={Sys.println("rhs");7;};Sys.println(box.value);',
				expected: 'address\nrhs\n7\n',
				catches: false
			},
			{
				name: 'array_calls',
				body: 'var items=[0];arrayReceiver(items)[arrayIndex()]={Sys.println("rhs");7;};Sys.println(items[0]);',
				expected: 'array\nindex\nrhs\n7\n',
				catches: false
			},
			{
				name: 'array_throw',
				body: 'var items=[0];try{arrayReceiver(items)[arrayIndex()]={Sys.println("rhs");throw "stop";7;};}catch(e:Dynamic){Sys.println("caught");}Sys.println(items[0]);',
				expected: 'array\nindex\nrhs\ncaught\n0\n',
				catches: true
			},
			{
				name: 'plain_calls',
				body: 'var box={value:0};receiver(box).value=right();Sys.println(box.value);',
				expected: 'receiver\nrhs\n7\n',
				catches: false
			},
			{
				name: 'return',
				body: 'var box={value:0};receiver(box).value={Sys.println("rhs");return;7;};Sys.println("bad");',
				expected: 'rhs\n',
				catches: false
			}
		];
		final methods = 'static function receiver(value:{value:Int}):{value:Int}{Sys.println("receiver");return value;}'
			+ 'static function arrayReceiver(value:Array<Int>):Array<Int>{Sys.println("array");return value;}'
			+ 'static function arrayIndex():Int{Sys.println("index");return 0;}'
			+ 'static function right():Int{Sys.println("rhs");return 7;}';
		for (entry in cases) {
			final source = 'class Main{' + methods + 'static function main():Void{' + entry.body + '}}';
			final root = '.tmp/control_assignment_' + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + '/Main.hx';
			sys.io.File.saveContent(path, source);
			if (Sys.command('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '-neko', root + '/upstream.n']) != 0)
				throw 'upstream assignment compilation failed';
			assertOutput('neko', [root + '/upstream.n'], entry.expected);
			Sys.println('UPSTREAM_CONTROL_ASSIGNMENT:PASS ' + entry.name);
			final module = new ResolvedModule('Main', path, ParserStage.parse(source, path));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			final functions = new Array<TypedFunction>();
			for (owner in typed.getTypedClasses())
				for (fn in owner.getFunctions())
					functions.push(fn);
			final revisions = functions.map(CompilerTypedTreeRevision.functionBody);
			for (fn in functions) {
				final lowered = TypedControlLowering.functionBody(fn);
				if (CompilerTypedTreeRevision.functionBody(lowered) != CompilerTypedTreeRevision.functionBody(TypedControlLowering.functionBody(lowered)))
					throw 'repeated assignment lowering changed its identities';
			}
			JsRuntimeFixture.assertRuntime(typed, 'Main', entry.expected);
			assertSourceUnchanged(functions, revisions);
			Sys.println('JS_CONTROL_ASSIGNMENT:PASS ' + entry.name);
			// Direct typing has no target-specific exception providers. The complete
			// Neko workload below uses the production loader for both catch cases.
			if (entry.catches)
				continue;
			final context = new backend.BackendContext(root, root + '/local.n', 'Main', true, false, HxDefineMap.fromRawDefines(['neko=1']));
			final generated = @:privateAccess backend.vm.NekoTargetCore.renderProgram(new MacroExpandedProgram([typed], false), context);
			sys.io.File.saveContent(root + '/local.neko', generated);
			if (Sys.command('nekoc', [root + '/local.neko']) != 0)
				throw 'generated assignment compilation failed';
			assertOutput('neko', [root + '/local.n'], entry.expected);
			assertSourceUnchanged(functions, revisions);
			Sys.println('NEKO_CONTROL_ASSIGNMENT:PASS ' + entry.name);
		}
		#if control_assignment_neko
		final root = '.tmp/control_assignment_full_neko';
		sys.FileSystem.createDirectory(root);
		// Separate functions retain the return case's own destination.
		final functions = [
			for (i in 0...cases.length)
				'static function case' + i + '():Void{' + cases[i].body + '}'
		];
		final calls = [for (i in 0...cases.length) 'case' + i + '();'];
		sys.io.File.saveContent(root + '/Main.hx', 'class Main{' + methods + functions.join('') + 'static function main():Void{' + calls.join('') + '}}');
		sys.io.File.saveContent(root + '/expected.stdout', cases.map(entry -> entry.expected).join(''));
		NekoRuntimeFixture.exercise(root, true);
		#end
	}

	/** Compare a real target process with the independently authored output. */
	static function assertOutput(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process('gtimeout', ['30', command].concat(arguments));
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
