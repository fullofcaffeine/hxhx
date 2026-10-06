/** Compare explicit Int and Dynamic storage at the same authored range boundary. */
class M14DynamicRangeBoundTest {
	static function main():Void {
		for (dynamicBound in [false, true]) {
			final source = 'class Main {static function main():Void {var end:'
				+ (dynamicBound ? 'Dynamic' : 'Int')
				+ '=3; var total=0; for(i in 0...end){total+=i;} Sys.println(total);}}';
			final root = '.tmp/dynamic_range_bound_' + dynamicBound;
			sys.FileSystem.createDirectory(root);
			sys.io.File.saveContent(root + '/Main.hx', source);
			if (Sys.command('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '-neko', root + '/upstream.n']) != 0)
				throw 'upstream range compilation failed';
			final process = new sys.io.Process('neko', [root + '/upstream.n']);
			final output = process.stdout.readAll().toString();
			final errors = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0 || output != '3\n')
				throw 'upstream range behavior differs: ' + output + errors;
			Sys.println('UPSTREAM_RANGE:PASS dynamic=' + dynamicBound);
			final module = new ResolvedModule('Main', root + '/Main.hx', ParserStage.parse(source, root + '/Main.hx'));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			JsRuntimeFixture.assertRuntime(typed, 'Main', '3\n');
			assertNeko(typed, root, '3\n');
			assertOcaml(typed, root, '3\n');
			Sys.println('LOCAL_RANGE:PASS dynamic=' + dynamicBound);
		}
		orderedBounds();
		rejectStaticBounds();
		rejectNativePayloads();
		Sys.println('DYNAMIC_RANGE_BOUND:PASS');
	}

	/** Both bound calls finish once before the body mutates their source storage. */
	static function orderedBounds():Void {
		final source = 'class Main {static function lower():Dynamic {Sys.println("lower"); return 1;}'
			+ 'static function upper(value:Dynamic):Dynamic {Sys.println("upper"); return value;}'
			+
			'static function main():Void {var limit=4; var total=0; for(i in lower()...upper(limit)){limit=1; if(i==2)continue; total+=i;} Sys.println(total);}}';
		final root = '.tmp/dynamic_range_order';
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + '/Main.hx', source);
		if (Sys.command('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '-neko', root + '/upstream.n']) != 0)
			throw 'upstream order compilation failed';
		final expected = 'lower\nupper\n4\n';
		final upstream = new sys.io.Process('neko', [root + '/upstream.n']);
		final output = upstream.stdout.readAll().toString();
		final errors = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code != 0 || output != expected)
			throw 'upstream range order differs: ' + output + errors;
		final module = new ResolvedModule('Main', root + '/Main.hx', ParserStage.parse(source, root + '/Main.hx'));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		JsRuntimeFixture.assertRuntime(typed, 'Main', expected);
		assertNeko(typed, root, expected);
		assertOcaml(typed, root, expected);
	}

	/** Dynamic permission cannot make a statically incompatible endpoint valid. */
	static function rejectStaticBounds():Void {
		for (entry in [
			{type: 'String', value: '"3"'},
			{type: 'Float', value: '3.5'},
			{type: 'Bool', value: 'true'}
		]) {
			final source = 'class Main {static function main():Void {var end:' + entry.type + '=' + entry.value + ';for(i in 0...end){}}}';
			final root = '.tmp/dynamic_range_invalid_' + entry.type;
			sys.FileSystem.createDirectory(root);
			sys.io.File.saveContent(root + '/Main.hx', source);
			final upstream = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '-neko', root + '/upstream.n']);
			upstream.stdout.readAll();
			final errors = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			if (code == 0 || errors.indexOf('should be Int') < 0)
				throw 'upstream invalid range contract changed: ' + errors;
			final module = new ResolvedModule('Main', root + '/Main.hx', ParserStage.parse(source, root + '/Main.hx'));
			var rejected = false;
			try
				TyperStage.typeResolvedModule(module, TyperIndex.build([module]))
			catch (error:TyperError) {
				if (error.message.indexOf('should be Int for a range bound') < 0)
					throw error;
				rejected = true;
			}
			if (!rejected)
				throw 'invalid static range bound accepted: ' + entry.type;
		}
	}

	/** Native Int loop storage must never reinterpret another boxed runtime category. */
	static function rejectNativePayloads():Void {
		final source = 'class Main {static function main():Void {'
			+ 'var stringBound:Dynamic="3";try {for(i in 0...stringBound){}}catch(error:String){Sys.println("string");}'
			+ 'var boolBound:Dynamic=false;try {for(i in 0...boolBound){}}catch(error:String){Sys.println("bool");}'
			+ 'var nullBound:Dynamic=null;try {for(i in 0...nullBound){}}catch(error:String){Sys.println("null");}'
			+ '}}';
		final root = '.tmp/dynamic_range_native_payloads';
		sys.FileSystem.createDirectory(root);
		final module = new ResolvedModule('Main', root + '/Main.hx', ParserStage.parse(source, root + '/Main.hx'));
		assertOcaml(TyperStage.typeResolvedModule(module, TyperIndex.build([module])), root, 'string\nbool\nnull\n');
	}

	/** Exercise boxed bounds through native compilation and actual execution. */
	static function assertOcaml(typed:TypedModule, root:String, expected:String):Void {
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), root + '/ocaml', true);
		final process = new sys.io.Process('gtimeout', ['30', executable]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected)
			throw 'native OCaml range differs: ' + output + errors;
	}

	/** Compile and execute the actual generated Neko artifact, without altering its source. */
	static function assertNeko(typed:TypedModule, root:String, expected:String):Void {
		final context = new backend.BackendContext(root, root + '/local.n', 'Main', true, false, HxDefineMap.fromRawDefines(['neko=1']));
		final source = @:privateAccess backend.vm.NekoTargetCore.renderProgram(new MacroExpandedProgram([typed], false), context);
		sys.io.File.saveContent(root + '/local.neko', source);
		if (Sys.command('nekoc', [root + '/local.neko']) != 0)
			throw 'generated Neko range failed compilation';
		final process = new sys.io.Process('gtimeout', ['30', 'neko', root + '/local.n']);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected)
			throw 'generated Neko range differs: ' + output + errors;
	}
}
