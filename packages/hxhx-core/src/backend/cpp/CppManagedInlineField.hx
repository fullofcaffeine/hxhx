package backend.cpp;

import backend.cpp.CppManagedRootedExpression.CppManagedRootedExpressionInput;

/**
	Emit an inline field's retained typed initializer into the caller's root.
	Inline fields have no mutable static slot. Each read uses its declaration's
	exact expression catalogs, including chained constants, without parsing source.
	The expansion path rejects cycles before native source can be published.
 */
function render(input:CppManagedRootedExpressionInput, occurrence:TypedBackendFieldOccurrence, destination:String, indent:String):Array<String> {
	if (input.statics == null)
		throw "managed inline field requires program ownership";
	final initializer = input.statics.inlineInitializer(occurrence);
	final identity = initializer.getField().getCanonicalKey();
	final path = input.inlineFields == null ? [] : input.inlineFields;
	if (path.indexOf(identity) >= 0)
		throw "cyclic managed inline field initializer: " + identity;
	final renderer = new CppManagedRootedExpression({
		owner: FieldInitializer(initializer),
		heap: input.heap,
		temporaryPrefix: input.temporaryPrefix + "inline_",
		resolve: input.resolve,
		resolveStatic: input.resolveStatic,
		statics: input.statics,
		casts: input.casts,
		classes: input.classes,
		enums: input.enums,
		defaultValue: input.defaultValue,
		resolveConstructor: input.resolveConstructor,
		resolveInstance: input.resolveInstance,
		inlineFields: path.concat([identity])
	});
	return [indent + "{"].concat(renderer.renderTransfer(HxFieldDecl.getInit(initializer.getDeclaration()), occurrence.getType(), destination, indent + "  "))
		.concat([indent + "}"]);
}
