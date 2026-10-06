package backend.cpp;

import backend.cpp.CppManagedCallContext.CppManagedEnclosingApplication;
import backend.cpp.CppManagedRootedExpression.CppManagedClosureLink;
import backend.cpp.CppManagedConstructor.CppManagedConstructorTarget;
import backend.cpp.CppManagedInstanceMethod.CppManagedInstanceMethodTarget;

/** The program's symbol allocator owns names; semantic identity remains in the projection. */
typedef CppManagedFunctionEmissionInput = {
	final projection:TypedBackendFunctionProjection;
	final rootSymbol:String;
	final symbolPrefix:String;
	final ?application:CppManagedFunctionApplication;
	final ?resolveStatic:String->CppManagedStaticTarget;
	final ?statics:CppManagedStaticStorage;
	final ?recordStack:Bool;
	final ?casts:CppManagedCastPlan;
	final ?classes:CppManagedClassStorage;
	final ?enums:CppManagedEnumDescriptors;
	final ?defaultValue:TyType->String;
	final ?resolveConstructor:String->CppManagedConstructorTarget;
	final ?resolveInstance:(TypedBackendInstanceCallOccurrence, Null<CppManagedEnclosingApplication>) -> CppManagedInstanceMethodTarget;
}

/** One exact executable owner and its allocated native entry name. */
private typedef ManagedEntry = {
	final owner:CppManagedFunctionOwner;
	final symbol:String;
	final environmentName:Null<String>;
}

/**
	Emit a method and all of its cataloged closures as one consistent native unit.
	Declarations precede bodies so parent/child order cannot break recursive links.
	The ABI owns hidden operands and source parameter transport; body access uses
	the same slots. Named defaults initialize incoming roots before captured cells.
	This does not adapt legacy carriers or choose program-level method names,
	runtime publication, or call targets. Instance entries
	root the receiver before parameter cells and share one receiver cell with
	descendant closures. This does not allocate the instance or select its layout.
 */
class CppManagedFunctionEmitter {
	final input:CppManagedFunctionEmissionInput;
	final plan:CppManagedStoragePlan;
	final entries:Array<ManagedEntry>;
	final links:Array<CppManagedClosureLink>;
	final initializers:Array<CppManagedInitializerFunctions>;

	public function new(input:CppManagedFunctionEmissionInput) {
		if (input == null
			|| input.projection == null
			|| !identifier(input.rootSymbol)
			|| !identifier(input.symbolPrefix)
			|| !StringTools.startsWith(input.symbolPrefix, "hxhx_function_"))
			throw "managed function emission requires an exact projection and allocated symbols";
		this.input = input;
		try {
			plan = new CppManagedStoragePlan(input.projection, input.classes, input.application);
		} catch (failure:haxe.Exception) {
			throw new haxe.Exception("managed function " + input.projection.getStableIdentity() + ": " + failure.message, failure);
		}
		for (argument in HxFunctionDecl.getArgs(input.projection.getDeclaration()))
			if (HxFunctionArg.getIsRest(argument))
				throw "managed root entry requires explicit rest parameter adaptation";
		entries = [{owner: Root(input.projection), symbol: input.rootSymbol, environmentName: null}];
		links = [];
		final expressions = input.projection.requireCaptureCatalog().getExpressions();
		for (index in 0...expressions.length) {
			final symbol = input.symbolPrefix + "_closure" + index;
			final environment = "hxhx_env_" + input.symbolPrefix + "_" + index;
			if (symbol == input.rootSymbol || environment == input.rootSymbol)
				throw "managed function symbols collide";
			entries.push({owner: Closure(expressions[index]), symbol: symbol, environmentName: environment});
			links.push({expression: expressions[index], environmentName: environment, entrySymbol: symbol});
		}
		final fields = input.classes == null ? [] : input.classes.constructorInitializers(input.projection, input.application);
		initializers = [
			for (index in 0...fields.length)
				new CppManagedInitializerFunctions(input, fields[index], input.symbolPrefix + "_initializer" + index)
		];
	}

	/** All symbols, parameter layouts, environment links, and bodies come from the same checked plan. */
	public function rootDeclaration():String {
		plan.assertCurrent();
		return "inline " + signature(entries[0]) + ";";
	}

	/** All symbols, parameter layouts, environment links, and bodies come from the same checked plan. */
	public function render():String {
		plan.assertCurrent();
		final lines = new Array<String>();
		for (initializer in initializers)
			lines.push(initializer.render());
		for (link in links)
			lines.push(new CppManagedEnvironmentEmitter(plan, link.expression, link.environmentName).render());
		for (entry in entries)
			lines.push("inline " + signature(entry) + ";");
		for (entry in entries) {
			final selected = plan.requireFunction(entry.owner);
			final access = new CppManagedLocalAccess({
				projection: input.projection,
				plan: plan,
				owner: entry.owner,
				parameters: [for (parameter in selected.abi.getParameters()) "hxhx_arg" + parameter.slot],
				temporaryPrefix: "hxhx_parameters_" + entry.symbol + "_",
				environmentName: entry.environmentName,
				environmentSymbol: entry.environmentName == null ? null : "hxhx_environment",
				receiverSymbol: selected.abi.getHiddenParameters().contains(ReceiverValue)
				|| selected.abi.getHiddenParameters().contains(ReceiverCell) ? "hxhx_receiver" : null});
			final rooted = new CppManagedRootedExpression({
				owner: CallableBody(access),
				callContext: CppManagedCallContext.fromFunction(input.application),
				heap: "hxhx_heap",
				temporaryPrefix: "hxhx_value_" + entry.symbol + "_",
				resolve: requireLink,
				resolveStatic: input.resolveStatic,
				statics: input.statics,
				casts: input.casts,
				classes: input.classes,
				enums: input.enums,
				defaultValue: input.defaultValue,
				resolveConstructor: input.resolveConstructor,
				resolveInstance: input.resolveInstance
			});
			final services = CppManagedBodyServices.fromExpression(rooted);
			lines.push("inline " + signature(entry) + " {");
			if (input.recordStack == true) {
				if (input.statics == null)
					throw "managed debug stack requires program-owned storage";
				for (line in CppManagedStackFrame.entry(input.projection, entry.owner, input.statics))
					lines.push(line);
			}
			lines.push("  (void)hxhx_heap;");
			if (entry.environmentName != null)
				lines.push("  (void)hxhx_environment;");
			for (parameter in selected.abi.getParameters())
				lines.push("  (void)hxhx_arg" + parameter.slot + ";");
			if (selected.abi.result == RootedResult)
				lines.push("  (void)hxhx_result;");
			if (access.receiver != null)
				lines.push(access.receiver.renderRoot("hxhx_heap"));
			final defaults = switch entry.owner {
				case Root(projection): projection.getDefaults();
				case Closure(_): [];
			};
			for (value in defaults)
				if (selected.abi.getParameters()[value.slot].storage != RootedParameter)
					throw "named default requires nullable incoming parameter transport";
			lines.push(access.parameters.render("hxhx_heap", (slot, destination) -> {
				final result = new Array<String>();
				for (value in defaults)
					if (value.slot == slot) {
						result.push("if (" + destination + ".get().kind() == hxhx::managed::ValueKind::Null) {");
						for (line in rooted.renderTransfer(value.expression, selected.abi.getParameters()[slot].type, destination, "  "))
							result.push(line);
						result.push("}");
					}
				return result;
			}));
			if (access.receiver != null)
				lines.push(access.receiver.renderCapture("hxhx_heap"));
			switch entry.owner {
				case Root(projection) if (input.classes != null):
					for (index in 0...initializers.length) {
						if (access.receiver == null)
							throw "instance initializer lost its constructor receiver root";
						for (line in CppManagedInstanceInitializer.render(input, initializers[index].application, access.receiver.value(),
							entry.symbol + "_init" + index + "_", initializers[index].requireLink))
							lines.push(line);
					}
				case _:
			}
			lines.push(new CppManagedFunctionBody(plan, entry.owner).render(selected.abi.result == RootedResult ? "hxhx_result" : null, null, services));
			lines.push("}");
		}
		plan.assertCurrent();
		return lines.join("\n");
	}

	function requireLink(expression:HxExpr):CppManagedClosureLink {
		plan.requireClosure(expression);
		for (link in links)
			if (link.expression == expression)
				return link;
		throw "managed function emission lacks the exact child entry link";
	}

	/** Hidden native operands cannot consume or reorder source parameter slots. */
	function signature(entry:ManagedEntry):String {
		return CppManagedEntrySignature.render(plan.requireFunction(entry.owner).abi, entry.symbol);
	}

	static function identifier(value:Null<String>):Bool
		return value != null && ~/^[A-Za-z_][A-Za-z0-9_]*$/.match(value);
}
