import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Check parameterless enum Map behavior through real providers and normal native emission. */
class M14CppManagedEnumMapTest {
	static function observe(command:String, arguments:Array<String>):String {
		final child = new sys.io.Process(command, arguments);
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0 || stderr.length != 0)
			throw 'enum Map observer failed: ' + stdout + stderr;
		return stdout;
	}

	static function main():Void {
		final root = 'test/oracle/cpp_managed_enum_map_seed';
		final expected = sys.io.File.getContent(root + '/expected.stdout');
		if (observe('haxe', ['-cp', root + '/src', '-main', 'Main', '--interp']) != expected)
			throw 'upstream enum Map contract changed';
		Sys.println('CPP_MANAGED_ENUM_MAP_UPSTREAM:PASS');
		final fixture = CppResolvedFixture.load({sourceRoot: root + '/src', mainModule: 'Main', requiredModules: ['haxe.ds.Map']});
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		final output = '.tmp/cpp-managed-enum-map';
		final result = CppTargetCore.emit(program, new BackendContext(output, null, 'Main', true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable || observe(result.entryPath, []) != expected)
			throw 'native enum Map output differs';
		sys.io.File.copy('test/cpp_managed_heap/EnumMapObserver.cpp', output + '/Observer.cpp');
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
				throw 'enum Map observer compile failed: ' + code;
			if (observe(timeout, ['60', binary]) != expected)
				throw 'collecting enum Map output differs';
		}
		Sys.println('CPP_MANAGED_ENUM_MAP:PASS');
	}
}
