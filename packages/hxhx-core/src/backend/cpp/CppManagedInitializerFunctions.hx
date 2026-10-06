package backend.cpp;

import backend.cpp.CppManagedFunctionEmitter.CppManagedFunctionEmissionInput;
import backend.cpp.CppManagedRootedExpression.CppManagedClosureLink;

/**
	Emit the real closures cataloged under one instance initializer. Native entry
	symbols are allocated beneath the owning constructor's unique prefix, while
	all expression, parameter, and capture facts remain owned by the field.
	Declarations precede bodies so nested closures can refer to their descendants.
 */
class CppManagedInitializerFunctions {
	public final projection:TypedBackendFieldInitializerProjection;
	public final application:CppManagedInitializerApplication;

	final input:CppManagedFunctionEmissionInput;
	final plan:CppManagedInitializerStorage;
	final links:Array<CppManagedClosureLink>;

	public function new(input:CppManagedFunctionEmissionInput, application:CppManagedInitializerApplication, prefix:String) {
		if (input == null || application == null || !~/^hxhx_function_[A-Za-z0-9_]+$/.match(prefix))
			throw "initializer functions require exact field ownership and allocated symbols";
		if (input.classes == null
			|| input.classes.constructorInitializers(input.projection, input.application)
				.filter(selected -> selected.projection == application.projection && selected.identity == application.identity)
				.length == 0)
			throw "initializer functions require their exact constructor owner";
		this.input = input;
		this.application = application;
		this.projection = application.projection;
		plan = new CppManagedInitializerStorage(projection, application);
		final expressions = projection.requireCaptureCatalog().getExpressions();
		if (input.recordStack == true && expressions.length > 0)
			throw "managed debug stack requires exact initializer closure frame metadata";
		links = [
			for (index in 0...expressions.length)
				{
					expression: expressions[index],
					entrySymbol: prefix + "_closure" + index,
					environmentName: "hxhx_env_" + prefix + "_" + index
				}
		];
	}

	public function requireLink(expression:HxExpr):CppManagedClosureLink {
		plan.requireClosure(expression);
		for (link in links)
			if (link.expression == expression)
				return link;
		throw "initializer closure lacks its exact entry link";
	}

	public function render():String {
		plan.assertCurrent();
		final lines = new Array<String>();
		for (link in links) {
			lines.push(new CppManagedEnvironmentEmitter(plan, link.expression, link.environmentName).render());
			lines.push("inline " + CppManagedEntrySignature.render(plan.requireClosure(link.expression).abi, link.entrySymbol) + ";");
		}
		for (link in links) {
			final owner = CppManagedFunctionOwner.Closure(link.expression);
			final abi = plan.requireFunction(owner).abi;
			final access = new CppManagedLocalAccess({
				initializer: projection,
				plan: plan,
				owner: owner,
				parameters: [for (parameter in abi.getParameters()) "hxhx_arg" + parameter.slot],
				temporaryPrefix: "hxhx_parameters_" + link.entrySymbol + "_",
				environmentName: link.environmentName,
				environmentSymbol: "hxhx_environment"
			});
			final rooted = new CppManagedRootedExpression({
				owner: CallableBody(access),
				callContext: CppManagedCallContext.fromInitializer(application),
				heap: "hxhx_heap",
				temporaryPrefix: "hxhx_value_" + link.entrySymbol + "_",
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
			lines.push("inline " + CppManagedEntrySignature.render(abi, link.entrySymbol) + " {");
			lines.push("  (void)hxhx_heap; (void)hxhx_environment;");
			for (parameter in abi.getParameters())
				lines.push("  (void)hxhx_arg" + parameter.slot + ";");
			if (abi.result == RootedResult)
				lines.push("  (void)hxhx_result;");
			lines.push(access.parameters.render("hxhx_heap"));
			lines.push(new CppManagedFunctionBody(plan,
				owner).render(abi.result == RootedResult ? "hxhx_result" : null, null, CppManagedBodyServices.fromExpression(rooted)));
			lines.push("}");
		}
		plan.assertCurrent();
		return lines.join("\n");
	}
}
