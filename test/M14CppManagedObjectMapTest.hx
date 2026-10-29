import backend.cpp.CppManagedFunctionEmitter;
import backend.cpp.CppManagedRuntime;

/** Compare an authored factory with upstream, then observe its emitted identity and lifetime behavior. */
class M14CppManagedObjectMapTest {
	static function observe(command:String, args:Array<String>):String {
		final process = new sys.io.Process(command, args);
		final output = process.stdout.readAll().toString();
		final error = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || error.length != 0)
			throw 'object Map observer failed: ' + output + error;
		return output;
	}

	static function main():Void {
		final root = 'test/oracle/cpp_managed_object_map_seed';
		final expected = sys.io.File.getContent(root + '/expected.stdout');
		if (observe('haxe', ['-cp', root + '/src', '-main', 'Main', '--interp']) != expected)
			throw 'upstream object Map behavior changed';
		Sys.println('CPP_MANAGED_OBJECT_MAP_UPSTREAM:PASS');
		final fixture = CppResolvedFixture.load({sourceRoot: root + '/src', mainModule: 'Main', requiredModules: ['haxe.ds.Map', 'Array']});
		final functions = fixture.main.getBackendProjection().getClasses()[0].getFunctions();
		var selected:Null<TypedBackendFunctionProjection> = null;
		for (fn in functions)
			if (HxFunctionDecl.getName(fn.getDeclaration()) == 'create')
				selected = fn;
		if (selected == null)
			throw 'object Map fixture lost its factory';
		final emitter = new CppManagedFunctionEmitter({projection: selected, rootSymbol: 'generated_object_map', symbolPrefix: 'hxhx_function_object_map'});
		final generated = emitter.render();
		final output = '.tmp/cpp-managed-object-map';
		sys.FileSystem.createDirectory(output);
		new CppManagedRuntime().publish(output);
		sys.io.File.saveContent(output + '/Generated.hpp', '#include "ManagedCallable.hpp"\n' + generated);
		sys.io.File.copy('test/cpp_managed_heap/ObjectMapObserver.cpp', output + '/Observer.cpp');
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
				throw 'object Map observer did not compile';
			if (observe(timeout, ['60', binary]) != expected)
				throw 'native object Map behavior differs from upstream';
		}
		Sys.println('CPP_MANAGED_OBJECT_MAP:PASS');
	}
}
