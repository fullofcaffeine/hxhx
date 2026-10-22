import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Run a reduced ordinary source program through upstream and normal C++ emission. */
class M14CppManagedNullTest {
	static function observe(command:String, args:Array<String>):Void {
		final child = new sys.io.Process(command, args);
		final out = child.stdout.readAll().toString();
		final err = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0 || out.length != 0 || err.length != 0)
			throw 'null observer failed (' + code + '): ' + out + err;
	}

	static function main():Void {
		final literal = TyType.fromHintText('Null');
		for (name in ['Int', 'Bool', 'Float', 'Void']) {
			final target = TyType.fromHintText(name);
			if (backend.cpp.CppManagedValueTransfer.accepts(target, literal))
				throw 'null acquired a scalar/default value: ' + name;
		}
		final integer = TyType.fromHintText('Int');
		if (backend.cpp.CppManagedValueTransfer.accepts(integer, TyType.nullable(integer)))
			throw 'nullable Int silently lost null';
		if (backend.cpp.CppManagedValueTransfer.accepts(TyType.fromHintText('String'), integer))
			throw 'ordinary transfer performed String conversion';
		final root = 'test/oracle/cpp_managed_null_seed/src';
		observe('haxe', ['-cp', root, '-main', 'Main', '--interp']);
		Sys.println('CPP_MANAGED_NULL_UPSTREAM:PASS');
		final fixture = CppResolvedFixture.load({sourceRoot: root, mainModule: 'Main', requiredModules: ['Array']});
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		final output = '.tmp/cpp-managed-null';
		final result = CppTargetCore.emit(program, new BackendContext(output, null, 'Main', true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable)
			throw 'null test did not build its normal target';
		observe(result.entryPath, []);
		// Bind the observer to the exact declared completion field, not a guessed slot.
		final projected = new backend.cpp.CppTypedProgramProjection(program);
		final storage = new backend.cpp.CppManagedStaticStorage(projected, 'hxhx_statics_program');
		var completed:Null<String> = null;
		for (module in projected.getModules())
			for (owner in module.projection.getClasses())
				for (fn in owner.getFunctions())
					for (statement in fn.getBody())
						TypedBackendSourceWalk.statement(statement, expression -> {
							final field = fn.findField(expression);
							if (field != null
								&& field.getField().getOwner().getCanonicalName() == 'Main'
								&& field.getField().getName() == 'completed') {
								if (field.getType().getSemanticKey() != 'primitive:Bool')
									throw 'completion witness changed type';
								completed = storage.member(field);
							}
						}, _ -> {});
		if (completed == null)
			throw 'null fixture lost its completion witness';
		sys.io.File.saveContent(output
			+ '/Completion.hpp',
			'bool sourceCompleted(hxhx::managed::Heap& heap) { return heap.requireStatic<'
			+ storage.nativeName
			+ '>()->'
			+ completed
			+ '.read().asBoolean(); }\n');
		sys.io.File.copy('test/cpp_managed_heap/NullObserver.cpp', output + '/Observer.cpp');
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
				throw 'null observer compile failed (' + code + ', ' + optimization + ')';
			observe(timeout, ['60', binary]);
		}
		Sys.println('CPP_MANAGED_NULL:PASS');
	}
}
