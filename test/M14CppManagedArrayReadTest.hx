import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Native defaults follow pinned C++ observations, not interpreter scalar-null behavior. */
class M14CppManagedArrayReadTest {
	static function observe(command:String, arguments:Array<String>):String {
		final child = new sys.io.Process(command, arguments);
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0 || stderr.length != 0)
			throw 'array read observer failed: ' + stdout + stderr;
		return stdout;
	}

	static function main():Void {
		final root = 'test/oracle/cpp_managed_array_read_seed';
		final expected = sys.io.File.getContent(root + '/expected.cpp.stdout');
		if (observe('haxe', ['-cp', root + '/src', '-main', 'Main', '--interp']) != sys.io.File.getContent(root + '/expected.interp.stdout'))
			throw 'upstream interpreter contrast changed';
		Sys.println('CPP_MANAGED_ARRAY_READ_INTERP:PASS');
		final fixture = CppResolvedFixture.load({sourceRoot: root + '/src', mainModule: 'Main', requiredModules: ['Array']});
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		final boundary = M14CppManagedArrayReadBoundaryFixture.header(new backend.cpp.CppTypedProgramProjection(program));
		Sys.println('CPP_MANAGED_ARRAY_READ_BOUNDARY:PASS');
		final output = '.tmp/cpp-managed-array-read';
		final result = CppTargetCore.emit(program, new BackendContext(output, null, 'Main', true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable || observe(result.entryPath, []) != expected)
			throw 'native array read output differs';
		sys.io.File.saveContent(output + '/NullRead.hpp', boundary);
		sys.io.File.copy('test/cpp_managed_heap/ArrayReadObserver.cpp', output + '/Observer.cpp');
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
				throw 'array read observer compile failed: ' + code;
			if (observe(timeout, ['60', binary]) != expected)
				throw 'collecting array read output differs';
		}
		Sys.println('CPP_MANAGED_ARRAY_READ:PASS');
	}
}
