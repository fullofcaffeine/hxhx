/** Explicit untyped method calls retain their receiver while deferring method lookup across argument statements. */
class M14UntypedCallControlTest {
	static function source(body:String):String {
		return 'abstract Handle(Dynamic){}class Main{'
			+ 'static function receiver(value:Handle):Handle{Sys.println("receiver");return value;}'
			+ 'static function known(value:Int):Int{return value;}'
			+ 'static function first(value:Int,owner:Handle):Int{return 1;}'
			+ 'static function second(value:Int,owner:Handle):Int{return 2;}'
			+ 'static function firstInt(a:Int,b:Int):Int{return 1;}'
			+ 'static function secondInt(a:Int,b:Int):Int{return 2;}'
			+ 'static function output(value:Dynamic):Void{Sys.println(value);}'
			+ 'static function main():Void{'
			+ body
			+ '}}';
	}

	static function main():Void {
		M14UntypedCallbackInputTest.main();
		// The unchecked cast models a foreign handle whose runtime object is known
		// to the fixture. It does not declare the method on the opaque source type.
		final initialize = 'var object={run:first};var handle:Handle=cast object;';
		final replace = 'object.run=second;';
		final cases = [
			{name: 'conditional', body: initialize + 'output(untyped handle.run(0,if(true)handle else handle));', expected: '1\n'},
			{name: 'lookup', body: initialize + 'output(untyped handle.run(0,{' + replace + 'handle;}));', expected: '2\n'},
			{name: 'receiver', body: initialize + 'var other:Handle=cast {run:second};output(untyped handle.run(0,{handle=other;handle;}));', expected: '1\n'},
			{
				name: 'receiver_call',
				body: initialize + 'output(untyped receiver(handle).run(0,{Sys.println("arg");handle;}));',
				expected: 'receiver\narg\n1\n'
			},
			{name: 'wrapped', body: initialize + 'output((untyped handle.run)(0,{' + replace + 'handle;}));', expected: '2\n'},
			{
				name: 'written_optional_untyped',
				body: initialize + 'var fn:(Int,?Handle)->Int=untyped handle.run;output(fn(0));',
				expected: '1\n'
			},
			{
				name: 'written_optional_cast',
				body: initialize + 'var fn:(Int,?Handle)->Int=cast object.run;output(fn(0));',
				expected: '1\n'
			},
			{
				name: 'unresolved_input',
				body: 'var object={run:first,value:0};var handle:Handle=cast object;var value=untyped handle.value;' +
				'var fn=untyped handle.run;output(fn(value,handle));',
				expected: '1\n'
			},
			{
				name: 'later_input_constraint',
				body: 'var object={run:first,value:7};var handle:Handle=cast object;var value=untyped handle.value;' +
				'var fn=untyped handle.run;var alias=fn;output(fn(value,handle));var concrete:Int=value;output(concrete);output(alias(1,handle));',
				expected: '1\n7\n1\n'
			},
			{name: 'known_field', body: 'var object={run:firstInt};output(untyped object.run(1,{object.run=secondInt;3;}));', expected: '1\n'}
		];
		for (entry in cases) {
			final root = '.tmp/untyped_call_control_' + entry.name;
			sys.FileSystem.createDirectory(root);
			final path = root + '/Main.hx';
			final text = source(entry.body);
			sys.io.File.saveContent(path, text);
			if (Sys.command('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '-neko', root + '/upstream.n']) != 0)
				throw 'upstream untyped call failed compilation';
			assertOutput(root + '/upstream.n', entry.expected);
			Sys.println('UPSTREAM_UNTYPED_CALL:PASS ' + entry.name);
			final module = new ResolvedModule('Main', path, ParserStage.parse(text, path));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			final functions = [for (owner in typed.getTypedClasses()) for (fn in owner.getFunctions()) fn];
			final revisions = functions.map(CompilerTypedTreeRevision.functionBody);
			for (fn in functions) {
				final lowered = TypedControlLowering.functionBody(fn);
				if (CompilerTypedTreeRevision.functionBody(lowered) != CompilerTypedTreeRevision.functionBody(TypedControlLowering.functionBody(lowered)))
					throw 'untyped call lowering changed on repeated application';
			}
			JsRuntimeFixture.assertRuntime(typed, 'Main', entry.expected);
			Sys.println('JS_UNTYPED_CALL:PASS ' + entry.name);
			final context = new backend.BackendContext(root, root + '/local.n', 'Main', true, false, HxDefineMap.fromRawDefines(['neko=1']));
			final generated = @:privateAccess backend.vm.NekoTargetCore.renderProgram(new MacroExpandedProgram([typed], false), context);
			sys.io.File.saveContent(root + '/local.neko', generated);
			if (Sys.command('nekoc', [root + '/local.neko']) != 0)
				throw 'generated untyped call failed compilation';
			assertOutput(root + '/local.n', entry.expected);
			for (i in 0...functions.length)
				if (CompilerTypedTreeRevision.functionBody(functions[i]) != revisions[i])
					throw 'untyped call lowering changed authored source';
			Sys.println('LOCAL_UNTYPED_CALL:PASS ' + entry.name);
		}
		assertClassGuard();
		assertRejected('known_argument', 'untyped known("bad");', 'No compatible method signature for known');
		assertRejected('stored_call_conflict', 'var handle:Handle=cast {};var fn=untyped handle.run;fn(1);fn("text");',
			'captured callback argument conflicts with its inferred type');
		assertRejected('aliased_call_conflict', 'var handle:Handle=cast {};var fn=untyped handle.run;var alias=fn;fn(1);alias("text");',
			'captured callback argument conflicts with its inferred type');
		assertRejected('later_input_conflict',
			'var handle:Handle=cast {};var value=untyped handle.value;var fn=untyped handle.run;' + 'fn(value);fn(1);fn("text");',
			'captured callback argument conflicts with its inferred type');
		assertRejected('outside_untyped', 'var handle:Handle=cast {};untyped 1;handle.missing(0,if(true)handle else handle);',
			'control lowering cannot materialize an unresolved operand');
	}

	/** Explicit untyped checking does not erase known argument types or grant permission to a following expression. */
	static function assertRejected(name:String, body:String, diagnostic:String):Void {
		final root = '.tmp/untyped_call_negative_' + name;
		sys.FileSystem.createDirectory(root);
		final path = root + '/Main.hx';
		final text = source(body);
		sys.io.File.saveContent(path, text);
		final upstream = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '-neko', root + '/upstream.n']);
		final output = upstream.stdout.readAll().toString();
		final errors = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code == 0 || (errors.indexOf('String should be Int') < 0 && errors.indexOf('has no field missing') < 0))
			throw 'upstream negative did not report the expected type error: ' + output + errors;
		var rejected = false;
		try {
			final module = new ResolvedModule('Main', path, ParserStage.parse(text, path));
			TyperStage.typeResolvedModule(module, TyperIndex.build([module])).getBackendProjection();
		} catch (error:haxe.Exception) {
			rejected = error.message.indexOf(diagnostic) >= 0;
		}
		if (!rejected)
			throw 'untyped checking changed the rejection contract for ' + name;
		Sys.println('UNTYPED_NEGATIVE:PASS ' + name);
	}

	/** Unknown class fields have a different upstream call order and must not enter the abstract-only lowering path. */
	static function assertClassGuard():Void {
		final text = StringTools.replace(source('var object={run:first};var handle:Handle=cast object;output(untyped handle.run(0,{object.run=second;handle;}));'),
			'abstract Handle(Dynamic){}', 'class Handle{public function new(){}}');
		final root = '.tmp/untyped_call_class_guard';
		sys.FileSystem.createDirectory(root);
		final path = root + '/Main.hx';
		sys.io.File.saveContent(path, text);
		if (Sys.command('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '-neko', root + '/upstream.n']) != 0)
			throw 'upstream class guard failed compilation';
		assertOutput(root + '/upstream.n', '1\n');
		final module = new ResolvedModule('Main', path, ParserStage.parse(text, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		var rejected = false;
		try
			typed.getBackendProjection()
		catch (error:haxe.Exception) {
			rejected = error.message.indexOf('control lowering cannot materialize an unresolved operand') >= 0;
		}
		if (!rejected)
			throw 'unknown class field incorrectly entered abstract call lowering';
		Sys.println('UNTYPED_CLASS_GUARD:PASS unsupported class call remains explicit');
	}

	/** Execute the generated artifact and compare it with the independently recorded upstream result. */
	static function assertOutput(path:String, expected:String):Void {
		final process = new sys.io.Process('gtimeout', ['30', 'neko', path]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected)
			throw 'untyped call output differs: ' + output + errors;
	}
}
