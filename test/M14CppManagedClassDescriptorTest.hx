import backend.cpp.CppManagedClassStorage;
import backend.cpp.CppManagedProgramEmitter;
import backend.cpp.CppManagedRuntime;
import backend.cpp.CppManagedRuntimeType.valueType;
import backend.cpp.CppTypedProgramProjection;

/** Class handles and instance layouts must share identity without sharing admission. */
class M14CppManagedClassDescriptorTest {
	/** Flush phase boundaries so a timed-out run identifies its unfinished operation. */
	static function phase(name:String):Void {
		Sys.println('CPP_MANAGED_CLASS_DESCRIPTOR_PHASE:' + name + ':' + Sys.time());
		Sys.stdout().flush();
	}

	static function load():MacroExpandedProgram {
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/cpp_managed_class_descriptor_seed/src", mainModule: "Main", requiredModules: []});
		return new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
	}

	/**
		Retain identical immutable typed input while giving each module a fresh
		projection cache. Equal semantic revisions must not authorize occurrences
		owned by a different projection; reparsing providers is unnecessary here.
	 */
	static function independentProjection(source:MacroExpandedProgram):CppTypedProgramProjection {
		final modules = [
			for (module in source.getTypedModules())
				new TypedModule(module.getParsed(), module.getEnv(), module.getTypedClasses(), module.getRevision(), module.getSourceOrigin(),
					module.getConditionalCompilation(), module.getGeneratedDeclarations())
		];
		final independent = new MacroExpandedProgram(modules, source.macroMode, source.getGeneratedOcamlModules());
		if (independent.getTypedProgramRevision().getCanonicalIdentity() != source.getTypedProgramRevision().getCanonicalIdentity())
			throw "foreign-program control changed its semantic revision";
		return new CppTypedProgramProjection(independent);
	}

	static function rejected(action:Void->Void, message:String):Void {
		try
			action()
		catch (error:haxe.Exception) {
			if (error.message.indexOf(message) < 0)
				throw error;
			return;
		}
		throw "descriptor accepted invalid ownership: " + message;
	}

	/** Keep the comparison body exact while independently choosing its descriptor plan. */
	static function comparison(fn:TypedBackendFunctionProjection, classes:CppManagedClassStorage):backend.cpp.CppManagedRootedExpression {
		final access = new backend.cpp.CppManagedLocalAccess({
			projection: fn,
			plan: new backend.cpp.CppManagedStoragePlan(fn),
			owner: Root(fn),
			parameters: ['a', 'b'],
			temporaryPrefix: 'hxhx_parameters_comparison_'
		});
		return new backend.cpp.CppManagedRootedExpression({
			owner: CallableBody(access),
			classes: classes,
			heap: 'heap',
			temporaryPrefix: 'hxhx_value_comparison_',
			resolve: _ -> throw 'comparison fixture has no closures'
		});
	}

	/** A sanitizer diagnostic must fail even when its process returns success. */
	static function observe(command:String, arguments:Array<String>):String {
		final child = new sys.io.Process(command, arguments);
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0 || stderr != "")
			throw "descriptor process failed: " + stdout + stderr;
		return stdout;
	}

	static function main():Void {
		phase('load');
		final source = load();
		phase('projection');
		final program = new CppTypedProgramProjection(source);
		final storage = new CppManagedClassStorage(program);
		final main = program.requireClass(program.requireClassIdentity("Main"));
		final pick = main.getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == "pick")[0];
		final occurrence = pick.getRuntimeTypeCatalog().getEntries()[0];
		final classType = occurrence.getTarget().getValueType();
		if (!backend.cpp.CppManagedClassValueType.selects(program, classType)
			|| backend.cpp.CppManagedClassValueType.selects(program, occurrence.getTarget().getInstanceType()))
			throw "class handle storage confused an instance with its class value";
		if (!backend.cpp.CppManagedClassEquality.selects('==', classType, classType, storage)
			|| !backend.cpp.CppManagedClassEquality.selects('!=', classType, classType, storage)
			|| backend.cpp.CppManagedClassEquality.selects('<', classType, classType, storage)
			|| backend.cpp.CppManagedClassEquality.selects('==', occurrence.getTarget().getInstanceType(), classType, storage)
			|| backend.cpp.CppManagedClassEquality.selects('==', classType, TyType.fromHintText('Dynamic'), storage)
			|| backend.cpp.CppManagedClassEquality.selects('==', classType, classType, null))
			throw 'class equality accepted unsupported operators, values, or missing ownership';
		rejected(() -> backend.cpp.CppManagedClassValueType.selects(program, TyType.nominal(new TyNominalTypeId("Class"), [])), "type parameter");
		if (backend.cpp.CppManagedStaticDefault.render(program, classType) != "hxhx::managed::Value{}"
			|| !new backend.cpp.CppManagedCastPlan(program).retainsNull(classType))
			throw "class handle default and null storage disagree";
		final symbol = storage.requireRuntimeDescriptor(occurrence);
		if (valueType(occurrence, storage).getSemanticKey() != occurrence.getTarget().getValueType().getSemanticKey())
			throw "class value was typed as an instance predicate";
		if (storage.render().indexOf('false, 0') < 0)
			throw "identity-only class descriptor acquired a layout";
		final initializer = main.getFieldInitializers()[0].getRuntimeTypeCatalog().getEntries()[0];
		if (storage.requireRuntimeDescriptor(initializer) != symbol)
			throw "initializer and method class handles lost declaration identity";
		phase('foreign-program');
		final foreign = independentProjection(source);
		final foreignMain = foreign.requireClass(foreign.requireClassIdentity("Main"));
		final foreignPick = foreignMain.getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == "pick")[0];
		final foreignOccurrence = foreignPick.getRuntimeTypeCatalog().getEntries()[0];
		if (foreignOccurrence == occurrence || foreignOccurrence.getExpression() == occurrence.getExpression())
			throw "foreign-program control reused an owned occurrence";
		final foreignStorage = new CppManagedClassStorage(foreign);
		foreignStorage.requireRuntimeDescriptor(foreignOccurrence);
		rejected(() -> foreignStorage.requireRuntimeDescriptor(occurrence), "another program");
		phase('ownership-and-emission');
		final copied = new TypedBackendRuntimeTypeOccurrence(pick.getStableIdentity(), pick.getBodyRevision(), occurrence.getTarget());
		rejected(() -> storage.requireRuntimeDescriptor(copied), "another program or occurrence");
		switch occurrence.getExpression() {
			case ECall(_, arguments):
				arguments.push(HxExpr.EInt(1));
				rejected(() -> storage.requireRuntimeDescriptor(occurrence), "mutat");
				arguments.pop();
			case _:
				throw "descriptor fixture lost its class-value marker";
		}
		if (storage.requireRuntimeDescriptor(occurrence) != symbol)
			throw "restored occurrence lost its descriptor identity";
		final layout = storage.requireType(occurrence.getTarget().getInstanceType());
		if (layout.symbol != symbol || layout.fields.length != 1 || storage.render().indexOf('true, 1') < 0)
			throw "instance admission replaced or lost the class identity";
		final entries:Array<backend.cpp.CppManagedProgramEmitter.CppManagedProgramFunction> = [
			{projection: pick, rootSymbol: "pickDescriptor", symbolPrefix: "hxhx_function_descriptor"}
		];
		for (name in ['same', 'different']) {
			final methods = main.getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == name);
			if (methods.length != 1)
				throw 'descriptor observer lost its equality method';
			final expression = switch methods[0].getBody()[0] {
				case SReturn(value, _): value;
				case _: throw 'comparison fixture lost its return';
			};
			final copiedExpression = switch expression {
				case EBinop(op, a, b): HxExpr.EBinop(op, a, b);
				case _: throw 'comparison fixture lost its binary operation';
			};
			final exact = comparison(methods[0], storage);
			if (exact.valueType(expression).getSemanticKey() != 'primitive:Bool')
				throw 'class comparison lost its Boolean result';
			rejected(() -> exact.valueType(copiedExpression), 'not an exact expression');
			rejected(() -> exact.render(copiedExpression, 'result', ''), 'not an exact expression');
			final wrongProgram = comparison(methods[0], foreignStorage);
			rejected(() -> wrongProgram.valueType(expression), 'cannot identify a foreign function owner');
			rejected(() -> wrongProgram.render(expression, 'result', ''), 'cannot identify a foreign function owner');
			entries.push({projection: methods[0], rootSymbol: 'compare_' + name, symbolPrefix: 'hxhx_function_' + name});
		}
		final declarations = new CppManagedProgramEmitter({
			functions: entries,
			output: [],
			classes: storage
		}).render();
		final expected = sys.io.File.getContent('test/oracle/cpp_managed_class_descriptor_seed/expected.stdout');
		phase('upstream');
		if (observe('haxe', [
			'-cp',
			'test/oracle/cpp_managed_class_descriptor_seed/src',
			'-main',
			'Main',
			'--interp'
		]) != expected)
			throw "upstream descriptor source contract changed";
		phase('native');
		final native = backend.cpp.CppTargetCore.emit(source,
			new backend.BackendContext('.tmp/cpp-class-descriptor-native', null, 'Main', true, true, new haxe.ds.StringMap()));
		if (!native.builtExecutable || observe(native.entryPath, []) != expected)
			throw "normal native descriptor transport differs";
		Sys.println('CPP_MANAGED_CLASS_DESCRIPTOR_NATIVE:PASS');
		final directory = '.tmp/cpp-managed-class-descriptor';
		new CppManagedRuntime().publish(directory);
		sys.io.File.saveContent(directory + '/Generated.hpp', '#include "ManagedCallable.hpp"\n' + storage.render() + '\n' + declarations);
		sys.io.File.copy('test/cpp_managed_heap/ClassDescriptorObserver.cpp', directory + '/Observer.cpp');
		final compiler = Sys.getEnv('CXX') == null ? 'clang++' : Sys.getEnv('CXX');
		final timeout = Sys.systemName() == 'Mac' ? 'gtimeout' : 'timeout';
		for (optimization in ['-O0', '-O2']) {
			phase('observer' + optimization);
			final binary = directory + '/observer' + optimization;
			if (Sys.command(timeout, [
				'60',
				compiler,
				'-std=c++17',
				optimization,
				'-g',
				'-fno-omit-frame-pointer',
				'-fsanitize=address,undefined',
				directory + '/Observer.cpp',
				'-o',
				binary
			]) != 0)
				throw "descriptor observer compilation failed";
			if (observe(timeout, ['60', binary]) != "")
				throw "descriptor observer produced unexpected output";
		}
		Sys.println('CPP_MANAGED_CLASS_DESCRIPTOR:PASS');
	}
}
