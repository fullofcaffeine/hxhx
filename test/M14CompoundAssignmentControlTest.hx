/** Compound updates retain the original destination and value before right-side control runs. */
class M14CompoundAssignmentControlTest {
	static function main():Void {
		final cases = [
			{
				name: 'compound_local',
				body: 'var value=2;value += {value=10;3;};Sys.println(value);',
				expected: '5\n',
				catches: false
			},
			{
				name: 'compound_receiver',
				body: 'var first={value:2};var second={value:10};var selected=first;selected.value += {selected=second;3;};Sys.println(first.value);Sys.println(second.value);',
				expected: '5\n10\n',
				catches: false
			},
			{
				name: 'compound_receiver_call',
				body: 'var box={value:2};receiver(box).value += {Sys.println("rhs");box.value=10;3;};Sys.println(box.value);',
				expected: 'receiver\nrhs\n5\n',
				catches: false
			},
			{
				name: 'compound_array',
				body: 'var items=[2];({Sys.println("array");items;})[arrayIndex()] += {Sys.println("rhs");items[0]=10;3;};Sys.println(items[0]);',
				expected: 'array\nindex\nrhs\n5\n',
				catches: false
			},
			{
				name: 'compound_string',
				body: 'var text="a";text += if(true){text="b";"c";}else "d";Sys.println(text);',
				expected: 'ac\n',
				catches: false
			},
			{
				name: 'compound_array_redirect',
				body: 'var first=[2];var second=[10];var selected=first;var i=0;selected[i] += {selected=second;i=1;3;};Sys.println(first[0]);Sys.println(second[0]);',
				expected: '5\n10\n',
				catches: false
			},
			{
				name: 'compound_shadow',
				body: 'var value=2;value += {var value=10;value;};Sys.println(value);',
				expected: '12\n',
				catches: false
			},
			{
				name: 'compound_result',
				body: 'var value=2;var result=(value *= {value=10;3;});Sys.println(result);Sys.println(value);',
				expected: '6\n6\n',
				catches: false
			},
			{
				name: 'compound_throw',
				body: 'var box={value:2};try{receiver(box).value += {Sys.println("rhs");throw "stop";3;};}catch(e:Dynamic){Sys.println("caught");}Sys.println(box.value);',
				expected: 'receiver\nrhs\ncaught\n2\n',
				catches: true
			},
			{
				name: 'compound_return',
				body: 'var box={value:2};receiver(box).value += {Sys.println("rhs");return;3;};Sys.println("bad");',
				expected: 'receiver\nrhs\n',
				catches: false
			},

		];
		final methods = 'static function receiver(value:{value:Int}):{value:Int}{Sys.println("receiver");return value;}'
			+ 'static function arrayIndex():Int{Sys.println("index");return 0;}';
		final nekoSources = new Array<{path:String, source:String}>();
		final nekoCalls = new Array<String>();
		final nekoExpected = new StringBuf();
		for (entry in cases) {
			final source = 'class Main{' + methods + 'static function main():Void{' + entry.body + '}}';
			final root = '.tmp/compound_control_' + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + '/Main.hx';
			sys.io.File.saveContent(path, source);
			if (Sys.command('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '-neko', root + '/upstream.n']) != 0)
				throw 'upstream assignment compilation failed';
			assertOutput('neko', [root + '/upstream.n'], entry.expected);
			Sys.println('UPSTREAM_COMPOUND_CONTROL:PASS ' + entry.name);
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
			Sys.println('JS_COMPOUND_CONTROL:PASS ' + entry.name);
			// Resolve the real Neko Array and exception providers once for all cases.
			// Each original body remains a separate function, so return still exits it.
			final owner = 'CompoundCase' + nekoSources.length;
			nekoSources.push({
				path: owner + '.hx',
				source: 'class ' + owner + '{' + methods + 'public static function run():Void{' + entry.body + '}}'
			});
			nekoCalls.push('Sys.println("' + entry.name + '");' + owner + '.run();');
			nekoExpected.add(entry.name + '\n' + entry.expected);
		}
		nekoSources.push({path: 'Main.hx', source: 'class Main{static function main():Void{' + nekoCalls.join('') + '}}'});
		assertNeko(nekoSources, nekoExpected.toString());
		M14CppCompoundControlTest.run();
	}

	/** A complete provider context executes every case, including throws, in both Neko layouts. */
	static function assertNeko(sources:Array<{path:String, source:String}>, expected:String):Void {
		final root = '.tmp/compound_control_neko';
		sys.FileSystem.createDirectory(root);
		final program = NekoSourceProgramFixture.build(sources);
		final functions = [
			for (module in program.getTypedModules())
				for (owner in module.getTypedClasses())
					for (fn in owner.getFunctions())
						fn
		];
		final revisions = functions.map(CompilerTypedTreeRevision.functionBody);
		Sys.println('NEKO_COMPOUND_CONTROL:TYPED cases=' + (sources.length - 1));
		final context = new backend.BackendContext(root, root + '/main.n', 'Main', true, false, HxDefineMap.fromRawDefines(['neko=1']));
		final result = backend.vm.NekoTargetCore.emit(program, context);
		assertSourceUnchanged(functions, revisions);
		assertOutput('neko', [result.entryPath], expected);
		Sys.println('NEKO_COMPOUND_CONTROL:PASS split');
		sys.io.File.saveContent(root + '/single.neko', @:privateAccess backend.vm.NekoTargetCore.renderProgram(program, context));
		assertSourceUnchanged(functions, revisions);
		if (Sys.command('nekoc', [root + '/single.neko']) != 0)
			throw 'generated compound assignment compilation failed';
		assertOutput('neko', [root + '/single.n'], expected);
		Sys.println('NEKO_COMPOUND_CONTROL:PASS single');
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
