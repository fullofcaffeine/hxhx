import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Compare managed Map tests with an independent upstream result through normal native emission. */
class M14CppManagedMapTypeTest {
	static function observe(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final error = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || error.length != 0)
			throw 'Map type observer failed (exit ' + code + '): ' + output + error;
		return output;
	}

	static function main():Void {
		final root = 'test/oracle/cpp_managed_map_type_seed';
		final expected = sys.io.File.getContent(root + '/expected.stdout');
		if (observe('haxe', ['-cp', root + '/src', '-main', 'Main', '--interp']) != expected)
			throw 'upstream Map type behavior differs from the independent expectation';
		Sys.println('CPP_MANAGED_MAP_TYPE_UPSTREAM:PASS');
		final fixture = CppResolvedFixture.load({
			sourceRoot: root + '/src',
			mainModule: 'Main',
			requiredModules: ['haxe.ds.Map', 'haxe.ds.IntMap', 'haxe.ds.StringMap', 'Array']
		});
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		final result = CppTargetCore.emit(program, new BackendContext('.tmp/cpp-managed-map-type', null, 'Main', true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable || observe(result.entryPath, []) != expected)
			throw 'managed Map type behavior differs from upstream';
		// This independent host observer changes the allocation budget, not the
		// generated source. Sanitizers check both optimized and unoptimized code.
		final output = '.tmp/cpp-managed-map-type';
		sys.io.File.copy('test/cpp_managed_heap/MapTypeObserver.cpp', output + '/Observer.cpp');
		final compiler = Sys.getEnv('CXX') == null ? 'clang++' : Sys.getEnv('CXX');
		final timeout = Sys.systemName() == 'Mac' ? 'gtimeout' : 'timeout';
		for (optimization in ['-O0', '-O2']) {
			final binary = output + '/observer' + optimization;
			if (Sys.command(timeout, [
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
			]) != 0)
				throw 'Map lifetime observer failed native compilation';
			if (observe(timeout, ['60', binary]) != expected)
				throw 'Map lifetime observer differs from upstream';
		}
		Sys.println('CPP_MANAGED_MAP_TYPE:PASS');
	}
}
