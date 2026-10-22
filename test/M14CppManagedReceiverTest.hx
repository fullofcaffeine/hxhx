import backend.cpp.CppManagedFunctionEmitter;
import backend.cpp.CppManagedRuntime;
import backend.cpp.CppManagedStoragePlan;
import backend.cpp.CppManagedLocalAccess;
import backend.cpp.CppManagedClosureAbi;

/** Emit real typed method bodies; an independent native observer exercises their lifetime contract. */
class M14CppManagedReceiverTest {
	static function rejected(action:Void->Void, diagnostic:String):Void {
		var observed = '';
		try
			action()
		catch (error:String)
			observed = error;
		if (observed.indexOf(diagnostic) < 0)
			throw 'expected ' + diagnostic + ', received ' + observed;
	}

	/** Transport cannot invent a receiver or borrow a descendant closure's this read. */
	static function controls(fn:TypedBackendFunctionProjection):Void {
		final name = HxFunctionDecl.getName(fn.getDeclaration());
		final plan = new CppManagedStoragePlan(fn);
		if (name == 'forward') {
			final access = new CppManagedLocalAccess({
				projection: fn,
				plan: plan,
				owner: Root(fn),
				parameters: [],
				temporaryPrefix: 'hxhx_parameters_owner_',
				receiverSymbol: 'receiver'
			});
			rejected(() -> access.receiverType(EThis), 'not an exact expression');
			final child = fn.requireCaptureCatalog().getExpressions()[0];
			rejected(() -> new CppManagedLocalAccess({
				projection: fn,
				plan: plan,
				owner: Closure(child),
				parameters: [],
				temporaryPrefix: 'hxhx_parameters_child_',
				receiverSymbol: 'receiver',
				environmentName: 'hxhx_env_child',
				environmentSymbol: 'environment'
			}), 'must obtain its receiver from the environment');
			final abi = plan.requireFunction(Root(fn)).abi;
			rejected(() -> abi.nativeSignature(), 'not a closure callable signature');
			rejected(() -> backend.cpp.CppManagedCallEmitter.renderAbi(abi, {
				heap: 'heap',
				calleeSetup: [],
				callee: 'method',
				arguments: [],
				destination: 'result',
				temporaryPrefix: 'hxhx_call_receiver_'
			}), 'explicit receiver operands');
		} else if (name == 'main') {
			rejected(() -> new CppManagedLocalAccess({
				projection: fn,
				plan: plan,
				owner: Root(fn),
				parameters: [],
				temporaryPrefix: 'hxhx_parameters_static_',
				receiverSymbol: 'receiver'
			}), 'requires an instance entry');
		}
	}

	/** Receiver type arguments come from the typed body, not the declaration's bare class name. */
	static function genericReceiver():Void {
		final source = 'class Main<T> { function test():Main<T> { return this; } }';
		final parsed = new ResolvedModule('Main', 'Main.hx', ParserStage.parse(source, 'Main.hx'));
		final typed = TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed])).getTypedClasses()[0].getFunctions()[0];
		final projection = TypedBodySource.functionProjection(typed);
		final plan = new CppManagedStoragePlan(projection);
		final access = new CppManagedLocalAccess({
			projection: projection,
			plan: plan,
			owner: Root(projection),
			parameters: [],
			temporaryPrefix: 'hxhx_parameters_generic_',
			receiverSymbol: 'receiver'
		});
		final receiver = access.receiverType(EThis);
		if (receiver.getSemanticKey() != projection.getReturnType().getSemanticKey() || receiver.getTypeArguments().length != 1)
			throw 'receiver transport erased the applied class parameter';
	}

	static function observe(command:String, args:Array<String>):String {
		final process = new sys.io.Process(command, args);
		final output = process.stdout.readAll().toString();
		final error = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || error.length != 0)
			throw 'receiver observer failed: ' + output + error;
		return output;
	}

	static function main():Void {
		final constructorAbi = new CppManagedClosureAbi(TyType.functionType([], TyType.fromHintText('Void')), false, ReceiverCell);
		rejected(() -> constructorAbi.nativeSignature(), 'not a closure callable signature');
		rejected(() -> backend.cpp.CppManagedCallEmitter.renderAbi(constructorAbi, {
			heap: 'heap',
			calleeSetup: [],
			callee: 'constructor',
			arguments: [],
			destination: null,
			temporaryPrefix: 'hxhx_call_receiver_'
		}), 'explicit receiver operands');
		final root = 'test/oracle/cpp_managed_receiver_seed';
		final expected = sys.io.File.getContent(root + '/expected.stdout');
		if (observe('haxe', ['-cp', root + '/src', '-main', 'Main', '--interp']) != expected)
			throw 'upstream receiver behavior changed';
		Sys.println('CPP_MANAGED_RECEIVER_UPSTREAM:PASS');
		genericReceiver();
		final path = root + '/src/Main.hx';
		final parsed = new ResolvedModule('Main', path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed]));
		final wanted = ['direct', 'self', 'capture', 'forward', 'ignore'];
		final sources = new Array<String>();
		for (fn in typed.getBackendProjection().getClasses()[0].getFunctions()) {
			final name = HxFunctionDecl.getName(fn.getDeclaration());
			controls(fn);
			if (wanted.indexOf(name) < 0)
				continue;
			sources.push(new CppManagedFunctionEmitter({projection: fn, rootSymbol: 'generated_' + name, symbolPrefix: 'hxhx_function_' + name}).render());
		}
		if (sources.length != wanted.length)
			throw 'receiver fixture lost a selected method';
		final output = '.tmp/cpp-managed-receiver';
		sys.FileSystem.createDirectory(output);
		new CppManagedRuntime().publish(output);
		sys.io.File.saveContent(output + '/Generated.hpp', '#include "ManagedCallable.hpp"\n' + sources.join('\n'));
		sys.io.File.copy('test/cpp_managed_heap/ReceiverObserver.cpp', output + '/Observer.cpp');
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
				throw 'receiver observer did not compile';
			if (observe(timeout, ['60', binary]) != expected)
				throw 'native receiver behavior differs from upstream';
		}
		Sys.println('CPP_MANAGED_RECEIVER:PASS');
	}
}
