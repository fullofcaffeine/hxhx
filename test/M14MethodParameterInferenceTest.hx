/** Body constraints must survive in declaration parameters and generated execution. */
class M14MethodParameterInferenceTest {
	/** Compare exact public facts: accepting a value as Dynamic must not invent an input annotation. */
	static function dynamicDestinations():Void {
		final root = 'test/fixtures/method_parameter_dynamic_context';
		final expected = 'alias.value=Unknown\ncall.value=Unknown\ndirect.value=Unknown\nexplicit.value=Dynamic\nlater.value=Int\nlocal.value=Unknown\nunused.value=Unknown\n';
		final process = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '--macro', 'UpstreamTypes.check()', '--no-output']);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw 'upstream Dynamic-destination parameter facts differ: ' + stdout + stderr;
		Sys.println('UPSTREAM_DYNAMIC_DESTINATION_PARAMETERS:PASS');
		final path = root + '/Main.hx';
		final module = new ResolvedModule('Main', path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final projection = typed.getBackendProjection();
		final observations:Array<String> = [];
		for (fn in projection.findClass(HxModuleDecl.getMainClass(projection.getDeclaration())).getFunctions())
			for (parameter in fn.getParameters())
				observations.push(HxFunctionDecl.getName(fn.getDeclaration()) + '.' + parameter.getBinding().getSourceName() + '='
					+ parameter.getBinding().getType().getDisplay());
		observations.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		if (observations.join('\n') + '\n' != expected)
			throw 'local Dynamic-destination parameter facts differ: ' + observations.join(', ');
		Sys.println('LOCAL_DYNAMIC_DESTINATION_PARAMETERS:PASS');
		final expectedRuntime = 'consume\n7\nconsume\nok\nconsume\ntrue\n';
		final runtime = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '--run', 'Main']);
		final runtimeOutput = runtime.stdout.readAll().toString();
		final runtimeErrors = runtime.stderr.readAll().toString();
		final runtimeCode = runtime.exitCode();
		runtime.close();
		if (runtimeCode != 0 || runtimeOutput != expectedRuntime)
			throw 'upstream omitted-input runtime differs: ' + runtimeOutput + runtimeErrors;
		assertNative(typed, '.tmp/method_parameter_dynamic_context', expectedRuntime);
		Sys.println('OMITTED_INPUT_DYNAMIC_NATIVE:PASS');
	}

	static function main():Void {
		dynamicDestinations();
		final intType = TyType.fromHintText('Int');
		final lengthType = TyType.anonymous(['length'], [intType]);
		var failures = 0;
		for (entry in [
			{
				name: 'explicit',
				hint: ':{length:Int}',
				body: 'var selected:Int=value.length; return selected;',
				argument: '{length:3}',
				expected: lengthType
			},
			{
				name: 'dynamic',
				hint: ':Dynamic',
				body: 'var selected:Int=value.length; return selected;',
				argument: '{length:3}',
				expected: TyType.fromHintText('Dynamic')
			},
			{
				name: 'scalar',
				hint: '',
				body: 'var selected:Int=value; return selected;',
				argument: '3',
				expected: intType
			},
			{
				name: 'field',
				hint: '',
				body: 'var selected:Int=value.length; return selected;',
				argument: '{length:3}',
				expected: lengthType
			},
			{
				name: 'alias',
				hint: '',
				body: 'var alias=value; var selected:Int=alias.length; return selected;',
				argument: '{length:3}',
				expected: lengthType
			},
			{
				name: 'nested',
				hint: '',
				body: 'var selected:Int=value.inner.length; return selected;',
				argument: '{inner:{length:3}}',
				expected: TyType.anonymous(['inner'], [lengthType])
			},
			{
				name: 'multiple',
				hint: '',
				body: 'var a:Int=value.first; var b:Int=value.second; return a+b;',
				argument: '{first:1,second:2}',
				expected: TyType.anonymous(['first', 'second'], [intType, intType])
			},
			{
				name: 'block_alias',
				hint: '',
				body: 'var selected = {var alias=value; var n:Int=alias.length; n;}; return selected;',
				argument: '{length:3}',
				expected: lengthType
			},
			{
				name: 'dynamic_alias',
				hint: ':{length:Int}',
				body: 'var alias:Dynamic=value; return alias.length;',
				argument: '{length:3}',
				expected: lengthType
			},
			{
				name: 'reverse',
				hint: '',
				body: 'var b:Int=value.second; var a:Int=value.first; return a+b;',
				argument: '{first:1,second:2}',
				expected: TyType.anonymous(['first', 'second'], [intType, intType])
			}
		]) {
			final root = '.tmp/method_parameter_inference_' + entry.name;
			final source = 'class Main {static function run(value' + entry.hint + '):Int {' + entry.body + '} static function main():Void {Sys.println(run('
				+ entry.argument + '));}}';
			sys.FileSystem.createDirectory(root);
			sys.io.File.saveContent(root + '/Main.hx', source);
			final process = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '--run', 'Main']);
			final output = process.stdout.readAll().toString();
			final errors = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0 || output != '3\n')
				throw 'upstream failed: ' + output + errors;
			Sys.println('UPSTREAM_METHOD_PARAMETER:PASS ' + entry.name);
			try {
				final module = new ResolvedModule('Main', root + '/Main.hx', ParserStage.parse(source, root + '/Main.hx'));
				final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
				var found = false;
				for (cls in typed.getTypedClasses())
					for (fn in cls.getFunctions()) {
						if (HxFunctionDecl.getName(fn.getSourceDeclaration()) != 'run')
							continue;
						found = true;
						final type = fn.getEnvironment().getParams()[0].getType();
						if (type.getSemanticKey() != entry.expected.getSemanticKey())
							throw 'parameter type ' + type.getSemanticKey() + ' differs from ' + entry.expected.getSemanticKey();
						if (entry.name == 'dynamic_alias')
							for (local in fn.getEnvironment().getLocals())
								if (local.getName() == 'alias' && !local.getType().isDynamic())
									throw 'written Dynamic alias lost its type';
					}
				if (!found)
					throw 'run declaration missing';
				JsRuntimeFixture.assertRuntime(typed, 'Main', '3\n');
				if (entry.hint.length == 0)
					assertNative(typed, root);
				Sys.println('LOCAL_METHOD_PARAMETER:PASS ' + entry.name);
			} catch (error:haxe.Exception) {
				failures++;
				Sys.println('LOCAL_METHOD_PARAMETER:FAIL ' + entry.name + ' ' + error.message);
			}
		}
		if (failures != 0)
			throw 'method parameter inference failures=' + failures;
		Sys.println('METHOD_PARAMETER_INFERENCE:PASS');
	}

	/** Compare a real native executable, including the expression-block alias replay path. */
	static function assertNative(module:TypedModule, root:String, expectedOutput:String = '3\n'):Void {
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([module], []), root + '/ocaml', true);
		final process = new sys.io.Process('gtimeout', ['30', executable]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expectedOutput)
			throw 'native inferred parameter result differs: ' + output + errors;
	}
}
