import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Native abstract construction must execute its whole body, including transformed initialization. */
class M14PrimitiveConstructorEffectsTest {
	static function main():Void {
		M14CppManagedInstanceMethodTest.main();
		final selected = M14SmokeGroupSelection.selected(['PrimitiveConstructorEffectsMain', 'ConstructorOrderMain', 'ReceiverValueMain']);
		final failures = new Array<String>();
		for (entry in [
			{name: "PrimitiveConstructorEffectsMain", expected: "primitive-effects.stdout"},
			{name: "ConstructorOrderMain", expected: "constructor-order.stdout"},
			{name: 'ReceiverValueMain', expected: 'receiver-value.stdout'}
		]) {
			if (selected != 'all' && selected != entry.name)
				continue;
			Sys.println('PRIMITIVE_CONSTRUCTOR_EFFECTS:START ' + entry.name);
			Sys.stdout().flush();
			try {
				check(entry.name, entry.expected);
				Sys.println('PRIMITIVE_CONSTRUCTOR_EFFECTS:PASS ' + entry.name);
			} catch (error:haxe.Exception) {
				failures.push(entry.name + ": " + error.message);
			}
		}
		if (failures.length != 0)
			throw failures.join("\n");
		Sys.println("PRIMITIVE_CONSTRUCTOR_EFFECTS:PASS");
	}

	/** Compile and observe each full source program without hiding a later failure behind an earlier one. */
	static function check(name:String, expected:String):Void {
		final root = "test/oracle/abstract_constructor_result_seed";
		final fixture = CppResolvedFixture.load({sourceRoot: root + '/src', mainModule: name, requiredModules: ['Std']});
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		final result = CppTargetCore.emit(program,
			new BackendContext(".tmp/primitive-constructor-effects-programs/" + name, null, name, true, true, fixture.defines));
		if (!result.builtExecutable)
			throw "constructor effects require a native executable";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent(root + "/" + expected))
			throw "native constructor effects differ: " + stdout + stderr;
		if (name == 'ReceiverValueMain')
			observeCollectingReceiver(root + '/' + expected);
	}

	/** Run the unchanged generated program with collection at every allocation and native memory checks. */
	static function observeCollectingReceiver(expected:String):Void {
		final output = '.tmp/primitive-constructor-effects-programs/ReceiverValueMain';
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
				'-I' + output + '/src',
				'test/cpp_managed_heap/AbstractReceiverObserver.cpp',
				'-o',
				binary
			]) != 0)
				throw 'abstract receiver observer compile failed';
			final process = new sys.io.Process(timeout, ['60', binary]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0 || stderr.length != 0 || stdout != sys.io.File.getContent(expected))
				throw 'collecting abstract receiver behavior differs: ' + stdout + stderr;
		}
	}
}
