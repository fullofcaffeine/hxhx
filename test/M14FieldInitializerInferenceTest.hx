/** Inferred callable storage must retain its value type before argument control is lowered. */
class M14FieldInitializerInferenceTest {
	static function main():Void {
		for (entry in [
			{
				name: 'explicit',
				annotated: true,
				qualified: false,
				forwarded: false
			},
			{
				name: 'inferred',
				annotated: false,
				qualified: false,
				forwarded: false
			},
			{
				name: 'qualified',
				annotated: false,
				qualified: true,
				forwarded: false
			},
			{
				name: 'forwarded',
				annotated: false,
				qualified: false,
				forwarded: true
			}
		]) {
			final annotated = entry.annotated;
			final source = 'class Main {static var callback'
				+ (annotated ? ':Dynamic' : '')
				+ (entry.forwarded ? '=later; static var later=create();' : '=create();')
				+ ' static function create():Dynamic {return function(a:Int,b:Null<Int>):Void {Sys.println(a);};}'
				+ 'static function main():Void {'
				+ (entry.forwarded ? 'callback=later;' : '')
				+ 'untyped '
				+ (entry.qualified ? 'Main.' : '')
				+ 'callback(7, if(true) null else 2);}}';
			final root = '.tmp/field_initializer_inference_' + entry.name;
			sys.FileSystem.createDirectory(root);
			sys.io.File.saveContent(root + '/Main.hx', source);
			final upstream = new sys.io.Process('node_modules/.bin/haxe', ['-cp', root, '--run', 'Main']);
			final output = upstream.stdout.readAll().toString();
			final errors = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			if (code != 0 || output != '7\n')
				throw 'upstream field contract differs: ' + output + errors;
			final module = new ResolvedModule('Main', root + '/Main.hx', ParserStage.parse(source, root + '/Main.hx'));
			final index = TyperIndex.build([module]);
			final field = index.getByFullName('Main').fieldInfo('callback');
			final headerType = field.getType().getSemanticKey();
			final typed = TyperStage.typeResolvedModule(module, index);
			JsRuntimeFixture.assertRuntime(typed, 'Main', '7\n');
			if (field.getType().getSemanticKey() != headerType || index.getByFullName('Main').fieldInfo('callback') != field)
				throw 'initializer inference mutated the field declaration';
			if (entry.name == 'inferred') {
				final declaration = HxClassDecl.getFields(HxModuleDecl.getMainClass(ResolvedModule.getParsed(module).getDecl()))[0];
				switch HxFieldDecl.getInit(declaration) {
					case ECall(_, arguments):
						arguments.push(EInt(0));
						var rejected = false;
						try
							index.getFieldInitializerTypes().result(field)
						catch (message:String) {
							if (message != 'field initializer type belongs to changed source')
								throw message;
							rejected = true;
						}
						arguments.pop();
						if (!rejected)
							throw 'field result survived changed initializer';
					case _:
						throw 'fixture requires a call initializer';
				}
			}
			Sys.println('FIELD_INITIALIZER_CASE:PASS ' + entry.name);
		}
		crossModule();
		cycles();
		Sys.println('FIELD_INITIALIZER_INFERENCE:PASS');
	}

	/** A reader can request an inferred field before its provider module's bodies are typed. */
	static function crossModule():Void {
		final sources = [
			{
				path: 'library.Provider',
				source: 'package library; class Provider {public static var callback=create(); static function create():Dynamic return null;}'
			},
			{
				path: 'Main',
				source: 'import library.Provider.callback; class Main {static function create():Int return 7; static function use():Void {untyped callback(7, if(true) null else 2);}}'
			}
		];
		for (reverse in [false, true]) {
			final modules = [
				for (source in sources)
					new ResolvedModule(source.path, source.path.split('.').join('/') + '.hx',
						ParserStage.parse(source.source, source.path.split('.').join('/') + '.hx'))
			];
			final index = TyperIndex.build(modules);
			if (reverse)
				modules.reverse();
			for (module in modules) {
				final typed = TyperStage.typeResolvedModule(module, index);
				for (owner in typed.getTypedClasses())
					for (fn in owner.getFunctions())
						TypedBodySource.functionProjection(fn);
			}
			final field = index.getByFullName('library.Provider').fieldInfo('callback');
			if (!field.getType().isUnknown() || !index.getFieldInitializerTypes().result(field).isDynamic())
				throw 'cross-module initializer result changed';
		}
	}

	/** Reentrant initializers cannot publish a fallback type as completed evidence. */
	static function cycles():Void {
		final source = 'class Main {static var left=untyped right; static var right=left; static function main():Void {}}';
		final module = new ResolvedModule('Main', 'Main.hx', ParserStage.parse(source, 'Main.hx'));
		final index = TyperIndex.build([module]);
		TyperStage.typeResolvedModule(module, index);
		for (name in ['left', 'right'])
			if (!index.getFieldInitializerTypes().result(index.getByFullName('Main').fieldInfo(name)).isUnknown())
				throw 'cyclic field initializer published a guessed result';
	}
}
