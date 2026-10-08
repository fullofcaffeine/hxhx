/** Compare supported core type values and instance checks with upstream through host observers. */
class M14JsCoreRuntimeTypeTest {
	public static function check():Void {
		for (name in ['Array', 'String'])
			checkType(name);
	}

	/** Keep one compile/execute harness while each core type owns its independent source and expected behavior. */
	static function checkType(name:String):Void {
		final root = 'test/fixtures/js_' + name.toLowerCase() + '_runtime_type';
		final output = '.tmp/js_' + name.toLowerCase() + '_runtime_type';
		sys.FileSystem.createDirectory(output);
		final expected = sys.io.File.getContent(root + '/expected.stdout');
		run('node_modules/.bin/haxe', ['-cp', root, '-main', 'Main', '-js', output + '/upstream.js']);
		if (run('node', [root + '/host.cjs', sys.FileSystem.fullPath(output + '/upstream.js')]) != expected)
			throw 'upstream core ' + name + ' behavior differs';
		Sys.println('JS_CORE_RUNTIME_UPSTREAM:PASS ' + name);
		final path = root + '/Main.hx';
		final source = new ResolvedModule('Main', path, ParserStage.parse(sys.io.File.getContent(path), path));
		final args = hxhx.Stage1Compiler.Stage1Args.parse(['-main', 'Main'], true);
		final standardRoot = hxhx.Stage1Compiler.Stage1Args.getStandardLibraryRoot(args);
		final index = TyperIndex.buildHeaders([source]);
		final loader = new ModuleLoader([standardRoot + '/js/_std', standardRoot], hxhx.Stage3SetupSupport.buildDefinesMap([], 'js', 'js-native'), index,
			null, true);
		loader.markResolvedAlready([source]);
		for (provider in ['Class', name])
			if (loader.ensureTypeAvailable(provider, '', []) == null)
				throw 'missing real provider: ' + provider;
		final typed = TyperStage.typeResolvedModule(source, index, loader, true);
		final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		new backend.js.JsBackend().emit(new MacroExpandedProgram([typed], false),
			new backend.BackendContext(output, output + '/candidate.js', 'Main', true, false, HxDefineMap.fromRawDefines(['js=1'])));
		if (run('node', [root + '/host.cjs', sys.FileSystem.fullPath(output + '/candidate.js')]) != expected)
			throw 'candidate core ' + name + ' behavior differs';
		if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
			throw 'core type emission changed typed source';
		Sys.println('JS_CORE_RUNTIME_TYPE:PASS ' + name);
	}

	static function main():Void {
		check();
	}

	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(Sys.systemName() == 'Mac' ? 'gtimeout' : 'timeout', ['60', command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw 'core runtime observer failed: ' + stdout + stderr;
		return stdout;
	}
}
