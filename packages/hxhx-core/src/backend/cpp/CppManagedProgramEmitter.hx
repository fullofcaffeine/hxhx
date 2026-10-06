package backend.cpp;

import backend.cpp.CppManagedCallContext.CppManagedEnclosingApplication;
import backend.cpp.CppManagedConstructor.CppManagedConstructorTarget;
import backend.cpp.CppManagedInstanceMethod.CppManagedInstanceMethodTarget;
import backend.cpp.CppManagedInstanceMethod.CppManagedInstanceMethodEntry;

/** The enclosing target chooses program symbols after resolving semantic declarations. */
typedef CppManagedProgramFunction = {
	final projection:TypedBackendFunctionProjection;
	final ?application:CppManagedFunctionApplication;
	final rootSymbol:String;
	final symbolPrefix:String;
}

/**
	Link exact static method declarations before emitting their managed bodies.
	Calls never resolve by source name or by the marker's rendered result type.
	All root declarations precede definitions, including calls to later methods.
	This assembly boundary does not publish runtime files or adapt legacy carriers.
 */
class CppManagedProgramEmitter {
	final targets:haxe.ds.StringMap<CppManagedStaticTarget> = new haxe.ds.StringMap();
	final functions:Array<CppManagedFunctionEmitter> = [];
	final statics:Null<CppManagedStaticStorage>;
	final casts:Null<CppManagedCastPlan>;
	final classes:Null<CppManagedClassStorage>;
	final enums:Null<CppManagedEnumDescriptors>;
	final defaultValue:Null<TyType->String>;
	final constructors = new haxe.ds.StringMap<CppManagedConstructorTarget>();
	final instanceMethods = new haxe.ds.StringMap<CppManagedInstanceMethodEntry>();

	public function new(program:{
		functions:Array<CppManagedProgramFunction>,
		output:Array<TyDeclarationInfo>,
		?runtimePredicates:Array<TyDeclarationInfo>,
		?standardStrings:Array<TyDeclarationInfo>,
		?downcasts:Array<TyDeclarationInfo>,
		?nativeStacks:Array<TyDeclarationInfo>,
		?recordStack:Bool,
		?statics:CppManagedStaticStorage,
		?casts:CppManagedCastPlan,
		?classes:CppManagedClassStorage,
		?enums:CppManagedEnumDescriptors,
		?defaultValue:TyType->String
	}) {
		if (program == null || program.output == null)
			throw "managed program requires an explicit native output inventory";
		final inputs = program.functions;
		statics = program.statics;
		casts = program.casts;
		classes = program.classes;
		enums = program.enums;
		defaultValue = program.defaultValue;
		if (inputs == null || inputs.length == 0)
			throw "managed program requires an exact method inventory";
		final symbols = new haxe.ds.StringMap<Bool>();
		for (input in inputs) {
			if (input == null || input.projection == null)
				throw "managed program method lacks its projection";
			if (input.application != null) {
				input.application.assertCurrent();
				if (input.application.projection != input.projection)
					throw "managed program application belongs to another function";
			}
			final identity = input.application == null ? input.projection.getStableIdentity() : input.application.identity;
			if (targets.exists(identity) || constructors.exists(identity) || instanceMethods.exists(identity))
				throw "managed program repeats a declaration identity";
			final declaration = input.projection.requireSemanticDeclaration();
			if (declaration.getIsStatic()) {
				if (input.application != null)
					throw "managed static application requires an explicit method argument plan";
				final target:CppManagedStaticTarget = Source(input.projection, input.rootSymbol);
				CppManagedStaticTarget.abi(target);
				targets.set(identity, target);
			} else {
				if (classes == null)
					throw 'managed instance method requires an explicit callable binding';
				if (input.application == null)
					throw 'managed instance entry requires its exact receiver application';
				if (!declaration.getHasBody())
					throw "managed instance entry cannot emit a bodyless contract";
				classes.assertFunction(input.projection);
				if (declaration.getSignature().getName() == 'new') {
					if (!input.projection.getReturnType().isVoid())
						throw 'managed constructor body must complete with Void';
					constructors.set(identity, {projection: input.projection, symbol: input.rootSymbol, application: input.application});
				} else {
					classes.methods.assertInstanceMethod(input.projection);
					instanceMethods.set(identity, {projection: input.projection, symbol: input.rootSymbol, application: input.application});
				}
			}
			final names = [input.rootSymbol];
			final closures = input.projection.requireCaptureCatalog().getExpressions();
			for (index in 0...closures.length) {
				names.push(input.symbolPrefix + "_closure" + index);
				names.push("hxhx_env_" + input.symbolPrefix + "_" + index);
			}
			for (name in names) {
				if (symbols.exists(name))
					throw "managed program native symbols collide";
				symbols.set(name, true);
			}
		}
		for (declaration in program.output) {
			final target:CppManagedStaticTarget = Output(declaration);
			final identity = CppManagedStaticTarget.identity(target);
			if (targets.exists(identity))
				throw "managed program repeats a declaration identity";
			targets.set(identity, target);
		}
		if (program.runtimePredicates != null)
			for (declaration in program.runtimePredicates) {
				final target:CppManagedStaticTarget = RuntimePredicate(declaration);
				final identity = CppManagedStaticTarget.identity(target);
				if (targets.exists(identity))
					throw "managed program repeats a declaration identity";
				targets.set(identity, target);
			}
		if (program.standardStrings != null)
			for (declaration in program.standardStrings) {
				final target:CppManagedStaticTarget = StandardString(declaration);
				final identity = CppManagedStaticTarget.identity(target);
				if (targets.exists(identity))
					throw "managed program repeats a declaration identity";
				targets.set(identity, target);
			}
		if (program.downcasts != null)
			for (declaration in program.downcasts) {
				final target:CppManagedStaticTarget = Downcast(declaration);
				final identity = CppManagedStaticTarget.identity(target);
				if (targets.exists(identity))
					throw "managed program repeats a declaration identity";
				targets.set(identity, target);
			}
		if (program.nativeStacks != null)
			for (declaration in program.nativeStacks) {
				if (statics == null)
					throw "managed native stack requires program-owned storage";
				final target:CppManagedStaticTarget = NativeStack(declaration, statics);
				final identity = CppManagedStaticTarget.identity(target);
				if (targets.exists(identity))
					throw "managed program repeats a declaration identity";
				targets.set(identity, target);
			}
		for (input in inputs)
			functions.push(new CppManagedFunctionEmitter({
				projection: input.projection,
				application: input.application,
				rootSymbol: input.rootSymbol,
				symbolPrefix: input.symbolPrefix,
				resolveStatic: resolve,
				statics: statics,
				recordStack: program.recordStack,
				casts: casts,
				classes: classes,
				enums: enums,
				defaultValue: defaultValue,
				resolveConstructor: resolveConstructor,
				resolveInstance: resolveInstance
			}));
	}

	function resolve(identity:String):CppManagedStaticTarget {
		final selected = targets.get(identity);
		if (selected == null)
			throw "managed program lacks the selected static declaration: " + identity;
		CppManagedStaticTarget.validate(selected);
		return selected;
	}

	function resolveConstructor(identity:String):CppManagedConstructorTarget {
		final selected = constructors.get(identity);
		if (selected == null)
			throw 'managed program lacks its selected constructor entry: ' + identity;
		return selected;
	}

	function resolveInstance(call:TypedBackendInstanceCallOccurrence, context:Null<CppManagedEnclosingApplication>):CppManagedInstanceMethodTarget {
		final application = classes.methods.instanceApplication(call, context);
		final target = instanceMethods.get(application.identity);
		final hasBody = application.projection.requireSemanticDeclaration().getHasBody();
		if (hasBody != (target != null) || (target != null && target.projection != application.projection))
			throw 'managed program lacks its exact instance method entry';
		final cases = classes.methods.instanceDispatch(call, context);
		if (cases == null && target == null)
			throw "managed bodyless contract requires reachable dispatch";
		final dispatch = cases == null ? null : [
			for (entry in cases) {
				final selected = instanceMethods.get(entry.application.identity);
				if (selected == null
					|| selected.projection != entry.application.projection) throw "managed program lacks a reachable virtual implementation";
				{descriptor: entry.descriptor, target: selected};
			}
		];
		return {
			projection: application.projection,
			entry: target,
			application: application,
			dispatch: dispatch
		};
	}

	/** Startup bodies use the same exact static-call inventory as ordinary methods. */
	public function renderInitializer(projection:TypedBackendFieldInitializerProjection, symbol:String):String {
		if (statics == null)
			throw "managed initializer requires program static storage";
		return try CppManagedInitializerEmitter.render({
			projection: projection,
			statics: statics,
			symbol: symbol,
			resolveStatic: resolve,
			casts: casts,
			classes: classes,
			enums: enums,
			defaultValue: defaultValue,
			resolveConstructor: resolveConstructor,
			resolveInstance: resolveInstance
		}) catch (failure:haxe.Exception) {
			throw new haxe.Exception("managed initializer failed for " + projection.getField().getCanonicalKey() + ": " + failure.message, failure);
		};
	}

	/** Build the complete unit before returning it, so failed linkage cannot publish partial output. */
	public function render():String {
		final lines = statics == null ? [] : [statics.render()];
		for (fn in functions)
			lines.push(fn.rootDeclaration());
		for (fn in functions)
			lines.push(fn.render());
		return lines.join("\n");
	}
}
