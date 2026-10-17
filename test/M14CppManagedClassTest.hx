import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Compare ordinary authored class behavior through upstream and the normal managed target. */
class M14CppManagedClassTest {
	static function rejected(action:Void->Void, diagnostic:String):Void {
		try
			action()
		catch (error:haxe.Exception) {
			if (error.message.indexOf(diagnostic) >= 0)
				return;
			throw error;
		}
		throw 'class ownership control accepted invalid facts: ' + diagnostic;
	}

	/** Equal declaration spelling cannot transfer construction authority between compilation requests. */
	static function ownershipControls():Void {
		function project():backend.cpp.CppTypedProgramProjection {
			final source = 'class Main { public function new(id:Int) {} static function main():Void { new Main(1); } }';
			final module = new ResolvedModule('Main', 'Main.hx', ParserStage.parse(source, 'Main.hx'));
			return new backend.cpp.CppTypedProgramProjection(new MacroExpandedProgram([TyperStage.typeResolvedModule(module, TyperIndex.build([module]))],
				false));
		}
		final program = project();
		final foreign = new backend.cpp.CppManagedClassStorage(project());
		final storage = new backend.cpp.CppManagedClassStorage(program);
		var checked = false;
		for (module in program.getModules())
			for (owner in module.projection.getClasses())
				for (fn in owner.getFunctions())
					for (occurrence in fn.getConstructorCatalog().getEntries()) {
						checked = true;
						storage.assertFunction(fn);
						storage.requireConstructor(occurrence);
						rejected(() -> {
							foreign.requireConstructor(occurrence);
						}, 'another program');
						switch occurrence.getExpression() {
							case ENew(path, arguments):
								rejected(() -> {
									fn.requireConstructor(ENew(path, arguments.copy()));
								}, 'constructor');
								final saved = arguments[0];
								arguments[0] = EInt(2);
								rejected(() -> {
									storage.requireConstructor(occurrence);
								}, 'arguments were replaced');
								arguments[0] = saved;
								storage.requireConstructor(occurrence);
							case _:
								throw 'constructor control lost its source expression';
						}
					}
		if (!checked)
			throw 'constructor ownership controls did not run';
		Sys.println('CPP_MANAGED_CLASS_OWNERSHIP:PASS');
	}

	static function observe(command:String, arguments:Array<String>):String {
		final child = new sys.io.Process(command, arguments);
		final output = child.stdout.readAll().toString();
		final errors = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0 || errors.length != 0)
			throw 'class observer failed: ' + output + errors;
		return output;
	}

	static function main():Void {
		ownershipControls();
		final root = 'test/oracle/cpp_managed_class_seed';
		final expected = sys.io.File.getContent(root + '/expected.stdout');
		if (observe('haxe', ['-cp', root + '/src', '-main', 'Main', '--interp']) != expected)
			throw 'upstream class behavior changed';
		Sys.println('CPP_MANAGED_CLASS_UPSTREAM:PASS');
		final fixture = CppResolvedFixture.load({sourceRoot: root + '/src', mainModule: 'Main', requiredModules: []});
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		final output = '.tmp/cpp-managed-class';
		final result = CppTargetCore.emit(program, new BackendContext(output, null, 'Main', true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable || observe(result.entryPath, []) != expected)
			throw 'native class output differs from upstream';
		sys.io.File.copy('test/cpp_managed_heap/ClassObserver.cpp', output + '/Observer.cpp');
		final compiler = Sys.getEnv('CXX') == null ? 'clang++' : Sys.getEnv('CXX');
		final timeout = Sys.systemName() == 'Mac' ? 'gtimeout' : 'timeout';
		for (optimization in ['-O0', '-O2']) {
			final binary = output + '/observer' + optimization;
			final code = Sys.command(timeout, [
				'60',
				compiler,
				'-std=c++17',
				optimization,
				'-g',
				'-fno-omit-frame-pointer',
				'-fsanitize=address,undefined',
				output + '/Observer.cpp',
				'-o',
				binary
			]);
			if (code != 0)
				throw 'class observer compile failed: ' + code + ' ' + optimization;
			if (observe(timeout, ['60', binary]) != expected)
				throw 'collecting class observer differs from upstream';
		}
		Sys.println('CPP_MANAGED_CLASS:PASS');
	}
}
