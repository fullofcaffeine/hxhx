/** Caller checking must consume body-inferred inputs while declaration headers retain their identity. */
class M14MethodInputPublicationTest {
	static function main():Void {
		partialInputDynamicBoundary();
		for (privateAccess in [false, true])
			for (bodyInferred in [false, true])
				dynamicOmittedInput(privateAccess, bodyInferred);
		for (capture in [false, true])
			for (valid in [true, false]) {
				final source = 'class Main {static function run(value):Int {var n:Int=value.length; return n;} '
					+ 'static function main():Void {'
					+ (capture ? 'var call=run; Sys.println(call(' : 'Sys.println(run(')
					+ (valid ? '{length:3}' : '{length:"bad"}')
					+ '));}}';
				checkSource(source, 'direct_' + capture + '_' + valid, valid);
			}
		checkSource('class Main {static function run(value):Int {var n:Int=value.length; if(n>0) return run({length:0})+n; return 0;} '
			+ 'static function main():Void {Sys.println(run({length:3}));}}',
			'recursive', true);
		for (capture in [false, true])
			checkSource('class Main {static function run(value):Int {var n:Int=value.length; return n;} '
				+ 'static function main():Void {var value={length:3,extra:"ok"}; '
				+ (capture ? 'var call=run; Sys.println(call(value));}}' : 'Sys.println(run(value));}}'),
				'bound_width_'
				+ capture, true);
		for (valid in [true, false])
			crossModule(valid);
		for (capture in [false, true])
			checkSource('class Main {static function run(value):Int {var n:Int=value.length; return n;} '
				+ 'static function main():Void {'
				+ (capture ? 'var call=run; Sys.println(call(' : 'Sys.println(run(')
				+ '{length:3,extra:"ok"}));}}',
				'literal_width_'
				+ capture, false);
		Sys.println('METHOD_INPUT_PUBLICATION:PASS');
	}

	/** Invoke an inferred record input through Dynamic, observing the field in the receiving function. */
	static function partialInputDynamicBoundary():Void {
		final root = '.tmp/method_input_partial_dynamic';
		sys.FileSystem.createDirectory(root);
		final source = 'class Main {static function consume(value:Dynamic):Void {Sys.println(value.foo);} '
			+ 'static function forward(value):Void {var field=value.foo; consume(value);} '
			+ 'static function main():Void {var invoke:Dynamic=forward; invoke({foo:7});}}';
		sys.io.File.saveContent(root + '/Main.hx', source);
		final process = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '--run', 'Main']);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != '7\n')
			throw 'upstream partial input Dynamic boundary differs: ' + output + errors;
		final module = new ResolvedModule('Main', root + '/Main.hx', ParserStage.parse(source, root + '/Main.hx'));
		final index = TyperIndex.build([module]);
		final typed = TyperStage.typeResolvedModule(module, index);
		JsRuntimeFixture.assertRuntime(typed, 'Main', '7\n');
		final owner = index.getByFullName('Main');
		final declaration = owner.declarationForSignature(owner.staticMethodCandidates('forward')[0]);
		final input = index.getMethodBodyResults().signature(declaration).getArgs()[0];
		if (!input.isAnonymous() || input.getAnonymousFieldNames().join(',') != 'foo' || !input.getAnonymousFieldTypes()[0].isUnknown())
			throw 'Dynamic boundary fabricated a concrete structural field type';
		Sys.println('METHOD_INPUT_PARTIAL_DYNAMIC:PASS');
	}

	/** Explicit Dynamic operands do not manufacture a resolved declaration input. */
	static function dynamicOmittedInput(privateAccess:Bool, bodyInferred:Bool):Void {
		final root = '.tmp/method_input_dynamic_omitted_' + privateAccess + '_' + bodyInferred;
		sys.FileSystem.createDirectory(root);
		final source = 'class Helper {public static function read(value, suffix:String):String {'
			+ (bodyInferred ? 'var n:Int=value; ' : '')
			+ 'return suffix;}} '
			+ 'class Main {static function call(value:Dynamic):String {return '
			+ (privateAccess ? '@:privateAccess ' : '')
			+ 'Helper.read(value,"ok");} static function main():Void {Sys.println(call(7));}}';
		sys.io.File.saveContent(root + '/Main.hx', source);
		final process = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '--run', 'Main']);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != 'ok\n')
			throw 'upstream omitted Dynamic input differs: ' + output + errors;
		final module = new ResolvedModule('Main', root + '/Main.hx', ParserStage.parse(source, root + '/Main.hx'));
		final index = TyperIndex.build([module]);
		final typed = TyperStage.typeResolvedModule(module, index);
		JsRuntimeFixture.assertRuntime(typed, 'Main', 'ok\n');
		if (!privateAccess && !bodyInferred) {
			final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), root + '/ocaml', true);
			final native = new sys.io.Process('gtimeout', ['30', executable]);
			final nativeOutput = native.stdout.readAll().toString();
			final nativeErrors = native.stderr.readAll().toString();
			final nativeCode = native.exitCode();
			native.close();
			if (nativeCode != 0 || nativeOutput != 'ok\n')
				throw 'native omitted Dynamic input differs: ' + nativeOutput + nativeErrors;
			Sys.println('METHOD_INPUT_DYNAMIC_OMITTED_NATIVE:PASS');
		}
		final owner = index.getByFullName('Main.Helper');
		final signature = owner.staticMethodCandidates('read')[0];
		final declaration = owner.declarationForSignature(signature);
		final input = index.getMethodBodyResults().signature(declaration).getArgs()[0];
		if (!signature.getArgs()[0].isUnknown()
			|| (bodyInferred ? input.getSemanticKey() != TyType.fromHintText('Int').getSemanticKey() : !input.isUnknown()))
			throw 'Dynamic call changed the declaration input evidence';
		if (TyAssignmentCompatibility.classify(TyType.unknown(), TyType.fromHintText('Dynamic'), Unchecked) != Unknown)
			throw 'arbitrary Unknown became compatible with Dynamic';
		Sys.println('METHOD_INPUT_DYNAMIC_OMITTED:PASS ' + privateAccess + '/' + bodyInferred);
	}

	static function upstream(root:String, valid:Bool):Void {
		final process = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '--run', 'Main']);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if ((code == 0) != valid || (valid && output != '3\n'))
			throw 'upstream method input contract differs: ' + output + errors;
	}

	static function checkSource(source:String, name:String, valid:Bool):Void {
		final root = '.tmp/method_input_publication_' + name;
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + '/Main.hx', source);
		upstream(root, valid);
		final module = new ResolvedModule('Main', root + '/Main.hx', ParserStage.parse(source, root + '/Main.hx'));
		final index = TyperIndex.build([module]);
		final owner = index.getByFullName('Main');
		final header = owner.staticMethodCandidates('run')[0];
		final declaration = owner.declarationForSignature(header);
		final original = header.getArgs()[0].getSemanticKey();
		var accepted = true;
		try {
			final typed = TyperStage.typeResolvedModule(module, index);
			if (valid)
				JsRuntimeFixture.assertRuntime(typed, 'Main', '3\n');
		} catch (error:TyperError) {
			accepted = false;
		}
		if (accepted != valid)
			throw 'local method input acceptance differs: ' + name;
		if (header.getArgs()[0].getSemanticKey() != original || owner.staticMethodCandidates('run')[0] != header)
			throw 'input inference mutated the declaration header';
		if (valid) {
			final inferred = index.getMethodBodyResults().signature(declaration).getArgs()[0];
			if (inferred.getSemanticKey() != TyType.anonymous(['length'], [TyType.fromHintText('Int')]).getSemanticKey())
				throw 'published method input differs: ' + inferred.getSemanticKey();
			final consumerView = index.getMethodBodyResults().signature(declaration);
			consumerView.getArgs()[0] = TyType.fromHintText('Dynamic');
			if (index.getMethodBodyResults().signature(declaration).getArgs()[0].getSemanticKey() != inferred.getSemanticKey())
				throw 'consumer signature mutation changed the checked input facts';
			final body = HxFunctionDecl.getBody(declaration.getSourceDeclaration());
			body.push(SExpr(EInt(0), HxPos.unknown()));
			var rejected = false;
			try
				index.getMethodBodyResults().signature(declaration)
			catch (message:String)
				rejected = message == 'method body result belongs to a changed declaration';
			body.pop();
			if (!rejected)
				throw 'checked inputs survived a changed body';
			final arguments = HxFunctionDecl.getArgs(declaration.getSourceDeclaration());
			final originalArgument = arguments[0];
			arguments[0] = new HxFunctionArg('value', 'Dynamic', HxFunctionArg.getDefaultValue(originalArgument));
			rejected = false;
			try
				index.getMethodBodyResults().signature(declaration)
			catch (message:String)
				rejected = message == 'method body result belongs to a changed declaration';
			arguments[0] = originalArgument;
			if (!rejected)
				throw 'checked inputs survived a changed annotation';
		}
		Sys.println('METHOD_INPUT_CASE:PASS ' + name);
	}

	/** Provider imports determine input owners even when the consumer has a same-spelled class. */
	static function crossModule(valid:Bool):Void {
		final root = '.tmp/method_input_modules_' + valid;
		sys.FileSystem.createDirectory(root);
		sys.FileSystem.createDirectory(root + '/library');
		final sources = [
			{name: 'Main',
				file: 'Main.hx',
				source: 'import library.Provider; import library.Value as LibraryValue; class Value {public var n:String; public function new(){n="bad";}} '
				+ 'class Main {static function main():Void {Sys.println(Provider.read({item:new '
				+ (valid ? 'LibraryValue' : 'Value')
				+ '()}));}}'},
			{
				name: 'library.Provider',
				file: 'library/Provider.hx',
				source: 'package library; import library.Value; class Provider {public static function read(value):Int {var item:Value=value.item; return item.n;}}'
			},
			{name: 'library.Value', file: 'library/Value.hx', source: 'package library; class Value {public var n:Int; public function new(){n=3;}}'}
		];
		for (source in sources)
			sys.io.File.saveContent(root + '/' + source.file, source.source);
		upstream(root, valid);
		for (reverse in [false, true]) {
			final modules = [
				for (source in sources)
					new ResolvedModule(source.name, root + '/' + source.file, ParserStage.parse(source.source, root + '/' + source.file))
			];
			if (reverse)
				modules.reverse();
			final index = TyperIndex.build(modules);
			var accepted = true;
			try {
				for (module in modules)
					TyperStage.typeResolvedModule(module, index);
			} catch (error:TyperError) {
				accepted = false;
			}
			if (accepted != valid)
				throw 'cross-module input acceptance differs: ' + valid + '/' + reverse;
			if (valid) {
				final owner = index.getByFullName('library.Provider');
				final declaration = owner.declarationForSignature(owner.staticMethodCandidates('read')[0]);
				final input = index.getMethodBodyResults().signature(declaration).getArgs()[0];
				if (input.getAnonymousFieldTypes()[0].getNominalIdentity().getCanonicalName() != 'library.Value')
					throw 'input inference used consumer imports';
			}
		}
		Sys.println('METHOD_INPUT_MODULES:PASS ' + valid);
	}
}
