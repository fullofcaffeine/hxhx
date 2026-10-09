/** Native range bounds retain constraints from authored untyped results without weakening known types. */
class M14UntypedRangeInferenceTest {
	static function main():Void {
		final cases = [
			{name: 'direct', body: 'untyped {for(i in 0...__dollar__asize(values))result++;}'},
			{name: 'stored', body: 'untyped {var end=__dollar__asize(values);var alias=end;for(i in 0...alias)result++;}'},
			{name: 'wrapped', body: 'var end=untyped __dollar__asize(values);for(i in 0...end)result++;'}
		];
		for (entry in cases) {
			final root = '.tmp/untyped_range_inference_' + entry.name;
			sys.FileSystem.createDirectory(root);
			// Dynamic is restricted to raw native array values supplied to the
			// primitive. Loop counters and the public result are ordinary Ints.
			final source = 'class Main{static function count(values:Dynamic):Int{var result=0;'
				+ entry.body
				+ 'return result;}static function output(value:Int):Void{Sys.println(value);}'
				+ 'static function main():Void{var raw:Dynamic=untyped __dollar__array(1,2,3);output(count(raw));}}';
			final path = root + '/Main.hx';
			sys.io.File.saveContent(path, source);
			if (Sys.command('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '-neko', root + '/upstream.n']) != 0)
				throw 'upstream range compilation failed';
			assertOutput(root + '/upstream.n');
			Sys.println('UPSTREAM_UNTYPED_RANGE:PASS ' + entry.name);
			final module = new ResolvedModule('Main', path, ParserStage.parse(source, path));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			final functions = [for (owner in typed.getTypedClasses()) for (fn in owner.getFunctions()) fn];
			final revisions = functions.map(CompilerTypedTreeRevision.functionBody);
			final context = new backend.BackendContext(root, root + '/local.n', 'Main', true, false, HxDefineMap.fromRawDefines(['neko=1']));
			final generated = @:privateAccess backend.vm.NekoTargetCore.renderProgram(new MacroExpandedProgram([typed], false), context);
			sys.io.File.saveContent(root + '/local.neko', generated);
			if (Sys.command('nekoc', [root + '/local.neko']) != 0)
				throw 'local range compilation failed';
			assertOutput(root + '/local.n');
			for (i in 0...functions.length)
				if (CompilerTypedTreeRevision.functionBody(functions[i]) != revisions[i])
					throw 'range projection mutated authored types';
			Sys.println('LOCAL_UNTYPED_RANGE:PASS ' + entry.name);
		}
		assertRejected('known_result', 'untyped {for(i in 0...text()) {}}');
		assertRejected('alias_conflict', 'var end=untyped missing();for(i in 0...end){}var wrong:String=end;');
		assertRejected('ordinary_unknown', 'for(i in 0...missing()){}');
	}

	/** Negative sources must fail independently upstream and in local typing or projection. */
	static function assertRejected(name:String, body:String):Void {
		final root = '.tmp/untyped_range_inference_' + name;
		sys.FileSystem.createDirectory(root);
		final source = 'class Main{static function text():String{return "3";}static function main():Void{' + body + '}}';
		final path = root + '/Main.hx';
		sys.io.File.saveContent(path, source);
		final upstream = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '-neko', root + '/upstream.n']);
		final output = upstream.stdout.readAll().toString();
		final errors = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		final expected = name == 'ordinary_unknown' ? 'Unknown identifier' : name == 'alias_conflict' ? 'Int should be String' : 'String should be Int';
		if (code == 0 || errors.indexOf(expected) < 0)
			throw 'upstream rejection differs: ' + output + errors;
		var diagnostic = '';
		try {
			final module = new ResolvedModule('Main', path, ParserStage.parse(source, path));
			TyperStage.typeResolvedModule(module, TyperIndex.build([module])).getBackendProjection();
		} catch (error:haxe.Exception) {
			diagnostic = error.message;
		}
		final localExpected = name == 'ordinary_unknown' ? 'range iteration requires concrete bound values' : name == 'alias_conflict' ? 'inferred value Int is not compatible with String' : 'String should be Int for a range bound';
		if (diagnostic.indexOf(localExpected) < 0)
			throw 'local range rejection differs for ' + name + ': ' + diagnostic;
		Sys.println('UNTYPED_RANGE_REJECTION:PASS ' + name + ': ' + diagnostic);
	}

	/** A real Neko process observes the compiled loop, not merely its generated source. */
	static function assertOutput(path:String):Void {
		final process = new sys.io.Process('gtimeout', ['30', 'neko', path]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != '3\n')
			throw 'range output differs: ' + output + errors;
	}
}
