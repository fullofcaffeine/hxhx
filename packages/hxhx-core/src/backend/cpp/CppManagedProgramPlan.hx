package backend.cpp;

import backend.cpp.CppManagedCallContext.CppManagedEnclosingApplication;
import backend.cpp.CppManagedProgramEmitter.CppManagedProgramFunction;

/** A program method retains its exact class owner alongside its executable projection. */
private typedef ManagedProgramMethod = {
	final owner:TypedBackendClassProjection;
	final projection:TypedBackendFunctionProjection;
}

/**
	Select the requested entry and every reachable static or instance method before publication.
	Only semantic declaration identities join calls to methods. Native output is
	an explicit standard binding; missing bodies never fall back to legacy carriers.
	Ordinary virtual calls also select overrides for reached allocations until no
	new body or allocation appears; only then may the target lists become immutable.
	Startup methods and fields follow the exact loaded-class schedule. Unsupported
	effects fail before any file is written instead of disappearing from execution.
 */
class CppManagedProgramPlan {
	final program:CppTypedProgramProjection;
	final emitter:CppManagedProgramEmitter;
	final entrySymbol:String;
	final statics:CppManagedStaticStorage;
	final enums:CppManagedEnumDescriptors;
	final classes:CppManagedClassStorage;
	final initializers:Array<{projection:TypedBackendFieldInitializerProjection, symbol:String}> = [];
	final startupSymbols:Array<String> = [];
	var hasRuntimePredicate:Bool = false;

	public function new(program:CppTypedProgramProjection, requestedMain:String, recordStack:Bool = false) {
		this.program = program;
		program.assertCurrent();
		classes = new CppManagedClassStorage(program);
		enums = new CppManagedEnumDescriptors(program);
		final methods = new haxe.ds.StringMap<ManagedProgramMethod>();
		final entries = new Array<ManagedProgramMethod>();
		for (module in program.getModules())
			for (owner in module.projection.getClasses()) {
				final facts = owner.requireSemanticFacts();
				for (projection in owner.getFunctions()) {
					final declaration = projection.requireSemanticDeclaration();
					if (declaration.getOwner().getCanonicalName() != facts.getClassIdentity()
						|| declaration.getModulePath() != facts.getModuleIdentity())
						throw "managed program method differs from its semantic class owner";
					final method:ManagedProgramMethod = {owner: owner, projection: projection};
					final identity = projection.getStableIdentity();
					if (methods.exists(identity))
						throw "managed program repeats a semantic declaration";
					methods.set(identity, method);
					if ((requestedMain == null || requestedMain.length == 0 || facts.getClassIdentity() == requestedMain)
						&& declaration.getIsStatic()
						&& declaration.getSignature().getName() == "main")
						entries.push(method);
				}
			}
		if (entries.length != 1)
			throw "managed C++ program requires one exact requested main entry";
		final entry = entries[0].projection;
		final signature = entry.requireSemanticDeclaration().getSignature();
		if (signature.getArgs().length != 0 || !entry.getReturnType().isVoid())
			throw "managed C++ main requires a parameterless Void signature";
		CppManagedRuntimeType.validate(entry.getRuntimeTypeCatalog(), classes, enums);
		final pending = [entry.getStableIdentity()];
		final applications = new haxe.ds.StringMap<CppManagedFunctionApplication>();
		final instanceCalls = new Array<backend.cpp.CppManagedMethods.CppManagedMethodUse>();
		// A declaration can have several concrete entries. Keep the authored owner
		// once, while reachability and symbols distinguish its applied storage.
		function enqueueApplication(application:CppManagedFunctionApplication):Void {
			application.assertCurrent();
			if (!application.projection.requireSemanticDeclaration().getHasBody())
				throw "managed executable entry requires an authored body";
			final owner = methods.get(application.projection.getStableIdentity());
			if (owner == null || owner.projection != application.projection)
				throw "managed application lost its exact program method";
			if (applications.exists(application.identity))
				return;
			methods.set(application.identity, owner);
			applications.set(application.identity, application);
			pending.push(application.identity);
		}
		function enqueueInstance(call:TypedBackendInstanceCallOccurrence, ?context:CppManagedEnclosingApplication):Void {
			final application = classes.methods.instanceApplication(call, context);
			// Interface declarations describe calls. Reachability below discovers
			// their concrete implementations without inventing an interface body.
			if (application.projection.requireSemanticDeclaration().getHasBody())
				enqueueApplication(application);
			if (instanceCalls.filter(use -> use.call == call
				&& CppManagedCallContext.identity(use.context) == CppManagedCallContext.identity(context))
				.length == 0)
				instanceCalls.push({call: call, context: context});
		}
		// Initializers own their catalogs. Follow their dependencies without
		// borrowing the constructor's or a synthetic method's expression facts.
		function enqueueInitializer(initializer:TypedBackendFieldInitializerProjection, ?application:CppManagedInitializerApplication):Void {
			CppManagedRuntimeType.validate(initializer.getRuntimeTypeCatalog(), classes, enums, CppManagedCallContext.fromInitializer(application));
			for (occurrence in initializer.getConstructorCatalog().getEntries())
				enqueueApplication(classes.constructorApplication(initializer.requireConstructor(occurrence.getExpression()),
					CppManagedCallContext.fromInitializer(application)));
			TypedBackendSourceWalk.expression(initializer.getExpression(), expression -> {
				final instance = classes.methods.initializerInstanceCall(initializer, expression);
				if (instance != null
					&& !CppManagedArrayPush.selects(instance)
					&& !CppManagedArrayJoin.selects(instance)
					&& !CppManagedMapGet.selects(instance))
					enqueueInstance(instance, CppManagedCallContext.fromInitializer(application));
				final call = TypedExactStaticCallSource.decode(expression);
				if (call != null)
					pending.push(call.declaration);
			});
		}
		final startup = new CppManagedStartupOrder(program).getClasses();
		final startupMethods = new Array<String>();
		for (owner in startup) {
			// Extern declarations describe host storage; native C++ does not execute their authored initializers.
			if (owner.requireSemanticFacts().getIsExtern())
				continue;
			// Enum singleton startup is driven by declared constructors, not synthetic helper bodies.
			switch owner.requireSemanticFacts().getNominalKind() {
				case EnumValue:
					continue;
				case _:
			}
			for (method in owner.getFunctions()) {
				final declaration = method.requireSemanticDeclaration();
				if (declaration.getSignature().getName() == "__init__" && declaration.getHasBody()) {
					if (!declaration.getIsStatic() || declaration.getSignature().getArgs().length != 0 || !method.getReturnType().isVoid())
						throw "managed class startup requires a parameterless static Void method";
					startupMethods.push(method.getStableIdentity());
					pending.push(method.getStableIdentity());
				}
			}
			for (initializer in owner.getFieldInitializers())
				if (initializer.getField().getIsStatic() && !initializer.getField().getIsInline()) {
					// Admit the initializer before selecting its storage defaults, just as
					// method bodies are checked before their native representation is built.
					initializers.push({projection: initializer, symbol: "hxhx_initializer_" + initializers.length});
					enqueueInitializer(initializer);
				}
		}
		final visited = new haxe.ds.StringMap<Bool>();
		final sources = new haxe.ds.StringMap<TypedBackendFunctionProjection>();
		final output = new Array<TyDeclarationInfo>();
		final runtimePredicates = new Array<TyDeclarationInfo>();
		final standardStrings = new Array<TyDeclarationInfo>();
		final downcasts = new Array<TyDeclarationInfo>();
		final nativeStacks = new Array<TyDeclarationInfo>();
		var cursor = 0;
		while (true) {
			while (cursor < pending.length) {
				final identity = pending[cursor++];
				if (visited.exists(identity))
					continue;
				visited.set(identity, true);
				final selected = methods.get(identity);
				if (selected == null)
					throw "managed program lacks its selected semantic declaration: " + identity;
				final declaration = selected.projection.requireSemanticDeclaration();
				final name = declaration.getSignature().getName();
				if (CppManagedRuntimePredicate.owns(declaration)
					&& selected.owner.requireSemanticFacts().getIsExtern()
					&& !declaration.getHasBody()) {
					CppManagedRuntimePredicate.requireDeclaration(declaration);
					runtimePredicates.push(declaration);
					hasRuntimePredicate = true;
					continue;
				}
				if (selected.owner.requireSemanticFacts().getIsExtern()
					&& !declaration.getHasBody()
					&& declaration.getOwner().getCanonicalName() == "Sys"
					&& declaration.getModulePath() == "Sys"
					&& (name == "print" || name == "println")) {
					CppManagedOutput.requireDeclaration(declaration);
					output.push(declaration);
					continue;
				}
				if (CppManagedStandardString.owns(declaration)
					&& selected.owner.requireSemanticFacts().getIsExtern()
					&& !declaration.getHasBody()) {
					CppManagedStandardString.requireDeclaration(declaration);
					standardStrings.push(declaration);
					continue;
				}
				if (CppManagedDowncast.owns(declaration)
					&& selected.owner.requireSemanticFacts().getIsExtern()
					&& !declaration.getHasBody()) {
					CppManagedDowncast.requireDeclaration(declaration);
					downcasts.push(declaration);
					hasRuntimePredicate = true;
					continue;
				}
				if (CppManagedNativeStack.owns(declaration)
					&& selected.owner.requireSemanticFacts().getIsExtern()
					&& !declaration.getHasBody()) {
					CppManagedNativeStack.requireDeclaration(declaration);
					nativeStacks.push(declaration);
					continue;
				}
				if (!declaration.getHasBody())
					throw "managed program requires an explicit native or instance binding: " + identity;
				if (!declaration.getIsStatic() && name != 'new')
					classes.methods.assertInstanceMethod(selected.projection);
				CppManagedRuntimeType.validate(selected.projection.getRuntimeTypeCatalog(), classes, enums,
					CppManagedCallContext.fromFunction(applications.get(identity)));
				sources.set(identity, selected.projection);
				for (initializer in classes.constructorInitializers(selected.projection, applications.get(identity)))
					enqueueInitializer(initializer.projection, initializer);
				for (occurrence in selected.projection.getConstructorCatalog().getEntries())
					enqueueApplication(classes.constructorApplication(selected.projection.requireConstructor(occurrence.getExpression()),
						CppManagedCallContext.fromFunction(applications.get(identity))));
				TypedBackendSourceWalk.functionDeclaration(selected.projection.getDeclaration(), expression -> {
					final instance = classes.methods.functionInstanceCall(selected.projection, expression);
					if (instance != null
						&& !CppManagedArrayPush.selects(instance)
						&& !CppManagedArrayJoin.selects(instance)
						&& !CppManagedMapGet.selects(instance))
						enqueueInstance(instance, CppManagedCallContext.fromFunction(applications.get(identity)));
					final call = TypedExactStaticCallSource.decode(expression);
					if (call != null)
						pending.push(call.declaration);
				}, _ -> {});
			}
			// A selected override can allocate another concrete receiver. Revisit
			// dispatch after each reachability pass until no new bodies are selected.
			final previous = pending.length;
			for (call in instanceCalls) {
				final cases = classes.methods.instanceDispatch(call.call, call.context);
				if (cases != null)
					for (entry in cases)
						enqueueApplication(entry.application);
			}
			if (pending.length == previous)
				break;
		}
		classes.methods.sealInstanceDispatch(instanceCalls);
		final identities = [for (identity in sources.keys()) identity];
		identities.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		final functions = new Array<CppManagedProgramFunction>();
		final symbols = new haxe.ds.StringMap<String>();
		var mainSymbol:Null<String> = null;
		for (index in 0...identities.length) {
			final symbol = "hxhx_method_" + index;
			symbols.set(identities[index], symbol);
			functions.push({
				projection: sources.get(identities[index]),
				application: applications.get(identities[index]),
				rootSymbol: symbol,
				symbolPrefix: "hxhx_function_" + index
			});
			if (identities[index] == entry.getStableIdentity())
				mainSymbol = symbol;
		}
		if (mainSymbol == null)
			throw "managed program lost its selected entry";
		entrySymbol = mainSymbol;
		for (identity in startupMethods) {
			final symbol = symbols.get(identity);
			if (symbol == null)
				throw "managed program lost a class startup method";
			startupSymbols.push(symbol);
		}
		statics = new CppManagedStaticStorage(program, "hxhx_statics_program", nativeStacks.length > 0);
		emitter = new CppManagedProgramEmitter({
			functions: functions,
			output: output,
			runtimePredicates: runtimePredicates,
			standardStrings: standardStrings,
			downcasts: downcasts,
			nativeStacks: nativeStacks,
			recordStack: recordStack && nativeStacks.length > 0,
			statics: statics,
			casts: classes.casts,
			defaultValue: type -> CppManagedStaticDefault.render(program, type),
			classes: classes,
			enums: enums
		});
	}

	/** Complete admission and source generation before the normal target publishes any artifact. */
	public function render():String {
		program.assertCurrent();
		final defaults = statics.renderDefaults("hxhx_storage");
		final sources = [emitter.render()];
		for (initializer in initializers)
			sources.push(emitter.renderInitializer(initializer.projection, initializer.symbol));
		// Body admission can select layouts for field-only uses. Emit their one
		// canonical descriptor table only after every body has completed planning.
		sources.unshift(enums.render());
		if (hasRuntimePredicate || classes.needsRuntimePredicate())
			sources.unshift(classes.renderRuntimePredicate());
		sources.unshift(classes.render());
		final startup = [
			"  hxhx::managed::Root<hxhx::managed::Ref<" + statics.nativeName + ">> hxhx_storage(heap);",
			"  " + statics.renderAllocation("heap", "hxhx_storage")
		];
		for (line in defaults)
			startup.push("  " + line);
		for (line in enums.renderSingletonStartup(statics, "heap", "hxhx_storage"))
			startup.push("  " + line);
		for (symbol in startupSymbols)
			startup.push("  " + symbol + "(heap);");
		for (initializer in initializers)
			startup.push("  " + initializer.symbol + "(heap);");
		program.assertCurrent();
		return '#include "ManagedCallable.hpp"\n#include "ManagedOutput.hpp"\n'
			+ sources.join("\n")
			+ "\nvoid hxhx_program_run(hxhx::managed::Heap& heap) {\n"
			+ startup.join("\n")
			+ "\n  "
			+ entrySymbol
			+ "(heap);\n}\nint main() {\n  hxhx::managed::Heap heap;\n  hxhx_program_run(heap);\n  return 0;\n}\n";
	}
}
