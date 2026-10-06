package backend.cpp;

import backend.cpp.CppManagedFunctionEmitter.CppManagedFunctionEmissionInput;
import backend.cpp.CppManagedRootedExpression.CppManagedClosureLink;

/**
	Evaluate one field through its own typed catalogs while the constructor roots
	its receiver. Commit the slot only after evaluation and conversion succeed.
	A parent constructor calls this boundary for its own fields when super enters
	that body; allocation-time defaults do not execute authored initialization.
 */
function render(input:CppManagedFunctionEmissionInput, application:CppManagedInitializerApplication, receiver:String, prefix:String,
		?resolve:HxExpr->CppManagedClosureLink):Array<String> {
	if (input.classes == null || receiver == null || !~/^[A-Za-z_][A-Za-z0-9_]*$/.match(prefix))
		throw "instance initialization requires rooted receiver and program storage";
	input.classes.assertFunction(input.projection);
	final constructor = input.projection.requireSemanticDeclaration();
	if (constructor.getIsStatic() || constructor.getSignature().getName() != "new")
		throw "instance initialization requires its exact constructor body";
	final projection = application.projection;
	final member = input.classes.initializerMember(application);
	// The constructor must select this exact applied field, including forwarded children.
	if (input.classes.constructorInitializers(input.projection, input.application)
		.filter(selected -> selected.projection == projection && selected.identity == application.identity)
		.length == 0)
		throw "instance initializer belongs to another constructor owner";
	final emitter = new CppManagedRootedExpression({
		owner: FieldInitializer(projection),
		initializerApplication: application,
		callContext: CppManagedCallContext.fromInitializer(application),
		heap: "hxhx_heap",
		temporaryPrefix: "hxhx_value_" + prefix,
		resolve: resolve == null ? _ -> {
			throw "managed instance initializer requires its own closure entry plan";
		} : resolve,
		resolveStatic: input.resolveStatic,
		statics: input.statics,
		casts: input.casts,
		classes: input.classes,
		enums: input.enums,
		defaultValue: input.defaultValue,
		resolveConstructor: input.resolveConstructor,
		resolveInstance: input.resolveInstance
	});
	final result = prefix + "result";
	final lines = [
		"  {",
		"    hxhx::managed::Root<hxhx::managed::Value> " + result + "(hxhx_heap);"
	];
	for (line in CppControlRegion.renderInitializer(projection, result, "    ", {
		statement: emitter.renderStatement,
		returnValue: emitter.renderControlValue,
		directReturn: (_, _, _) -> {
			throw "field initializer cannot return from a function";
		},
		rootedValue: (value, destination, indent) -> emitter.renderTransfer(value, CppManagedInstanceField.transportType(member), destination, indent),
		forLoop: emitter.renderFor,
		switchArms: emitter.renderSwitch,
		tryRegion: emitter.renderTry
	}))
		lines.push(line);
	lines.push("    "
		+ receiver
		+ ".asManaged().as<hxhx::managed::InstancePayload>()->write("
		+ member.layout.symbol
		+ ", "
		+ member.slot
		+ ", "
		+ result
		+ ".get());");
	lines.push("  }");
	input.classes.assertInitializer(projection);
	return lines;
}
