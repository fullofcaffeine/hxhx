/** Body constraints must survive in declaration parameters and generated execution. */
class M14MethodParameterInferenceTest {
	static function main():Void {
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
	static function assertNative(module:TypedModule, root:String):Void {
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([module], []), root + '/ocaml', true);
		final process = new sys.io.Process('gtimeout', ['30', executable]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != '3\n')
			throw 'native inferred parameter result differs: ' + output + errors;
	}
}
