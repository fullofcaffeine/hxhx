import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Exercise source Map.get through production emission, with independent upstream output. */
class M14CppManagedMapGetTest {
	static function rejects(action:Void->Void):Void {
		var rejected = false;
		try {
			action();
		} catch (_:haxe.Exception) {
			rejected = true;
		}
		if (!rejected)
			throw "instance-call ownership accepted foreign or mutated facts";
	}

	/** Marker text, copied objects, and unrelated method spelling cannot authorize a native binding. */
	static function assertCallOwnership(program:MacroExpandedProgram):Void {
		var found = false;
		var unrelated = false;
		var initializer = false;
		var namedKey = false;
		final classes = new backend.cpp.CppManagedClassStorage(new backend.cpp.CppTypedProgramProjection(program));
		for (module in program.getTypedModules())
			for (cls in module.getBackendProjection().getClasses()) {
				for (fn in cls.getFunctions())
					for (statement in fn.getBody())
						TypedBackendSourceWalk.statement(statement, expression -> {
							final call = fn.findInstanceCall(expression);
							if (call == null)
								return;
							if (!namedKey && backend.cpp.CppManagedMapGet.selects(call)) {
								final key = call.getArgumentTypes()[0].getNominalIdentity();
								if (key != null && key.getCanonicalName() == 'Main.Key') {
									rejects(() -> backend.cpp.CppManagedMapGet.require(call));
									backend.cpp.CppManagedMapGet.require(call, classes);
									namedKey = true;
								}
							}
							if (call.getDeclaration().getOwner().getCanonicalName() == "Main.Other") {
								if (backend.cpp.CppManagedMapGet.selects(call))
									throw "unrelated get method selected Map storage";
								unrelated = true;
							}
							if (!found && backend.cpp.CppManagedMapGet.selects(call)) {
								found = true;
								rejects(() -> call.assertCurrent("foreign", fn.getBodyRevision()));
								switch expression {
									case ECall(callee, arguments):
										if (fn.findInstanceCall(ECall(callee, arguments.copy())) != null)
											throw "copied marker borrowed call facts";
										final saved = arguments[0];
										arguments[0] = EString("foreign");
										rejects(() -> {
											fn.findInstanceCall(expression);
										});
										arguments[0] = saved;
										if (fn.findInstanceCall(expression) != call) throw "restored call lost its owner";
									case _: throw "instance call lost its marker";
								}
							}
						}, _ -> {});
				for (field in cls.getFieldInitializers()) {
					final call = field.findInstanceCall(field.getExpression());
					if (call != null && backend.cpp.CppManagedMapGet.selects(call))
						initializer = true;
				}
			}
		if (!found || !unrelated || !initializer || !namedKey)
			throw "call ownership fixture lost a required control";
	}

	static function observe(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stderr.length != 0)
			throw 'Map.get observer failed: ' + stdout + stderr;
		return stdout;
	}

	static function main():Void {
		final root = 'test/oracle/cpp_managed_map_get_seed';
		final expected = sys.io.File.getContent(root + '/expected.stdout');
		if (observe('haxe', ['-cp', root + '/src', '-main', 'Main', '--interp']) != expected)
			throw 'upstream Map.get output changed';
		Sys.println('CPP_MANAGED_MAP_GET_UPSTREAM:PASS');
		final fixture = CppResolvedFixture.load({sourceRoot: root + '/src', mainModule: 'Main', requiredModules: ['haxe.ds.Map']});
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		assertCallOwnership(program);
		final result = CppTargetCore.emit(program, new BackendContext('.tmp/cpp-managed-map-get', null, 'Main', true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable || observe(result.entryPath, []) != expected)
			throw 'native Map.get output differs';
		final output = '.tmp/cpp-managed-map-get';
		sys.io.File.copy('test/cpp_managed_heap/MapTypeObserver.cpp', output + '/Observer.cpp');
		final compiler = Sys.getEnv('CXX') == null ? 'clang++' : Sys.getEnv('CXX');
		final timeout = Sys.systemName() == 'Mac' ? 'gtimeout' : 'timeout';
		for (optimization in ['-O0', '-O2']) {
			final binary = output + '/observer' + optimization;
			final compileCode = Sys.command(timeout, [
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
			if (compileCode != 0)
				throw 'Map.get collecting observer failed to compile (exit ' + compileCode + ', ' + optimization + ')';
			if (observe(timeout, ['60', binary]) != expected)
				throw 'Map.get collecting observer differs from upstream';
		}
		Sys.println('CPP_MANAGED_MAP_GET:PASS');
	}
}
