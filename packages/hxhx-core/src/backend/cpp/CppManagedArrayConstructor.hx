package backend.cpp;

import backend.cpp.CppManagedCallContext.CppManagedEnclosingApplication;

/** The standard zero-argument Array constructor allocates native storage without an authored body. */
function selects(occurrence:TypedBackendConstructorOccurrence):Bool {
	final type = occurrence.getConstructedType();
	return type.getNominalIdentity() != null && type.getNominalIdentity().getCanonicalName() == "Array";
}

/** Require the exact owned standard declaration and applied element type before choosing physical storage. */
function require(occurrence:TypedBackendConstructorOccurrence, context:Null<CppManagedEnclosingApplication>, classes:CppManagedClassStorage):TyType {
	classes.requireConstructorOwner(occurrence, context);
	final application = occurrence.requireApplication();
	final declaration = application.getDeclaration();
	final type = CppManagedCallContext.resolveType(context, occurrence.getConstructedType());
	CppManagedClosureAbi.assertComplete(type);
	if (!selects(occurrence)
		|| occurrence.getIsSuperCall()
		|| occurrence.getArguments().length != 0
		|| declaration.getOwner().getCanonicalName() != "Array"
		|| declaration.getModulePath() != "Array"
		|| declaration.getIsStatic()
		|| declaration.getIsDynamic()
		|| declaration.getTypeParameters().length != 0
		|| declaration.getSignature().getName() != "new"
		|| declaration.getSignature().getArgs().length != 0
		|| type.getTypeArguments().length != 1
		|| occurrence.requireArgumentBinding().getSlots().length != 0
		|| CppManagedCallContext.resolveType(context, application.getOwnerType()).getSemanticKey() != type.getSemanticKey())
		throw "managed Array construction requires its exact zero-argument standard constructor";
	return type;
}

/** Publish the same empty storage used by an Array literal, preserving its selected element representation. */
function render(occurrence:TypedBackendConstructorOccurrence, context:Null<CppManagedEnclosingApplication>, classes:CppManagedClassStorage, heap:String,
		destination:String, indent:String):Array<String> {
	final type = require(occurrence, context, classes);
	final array = destination + "_array";
	return [indent + "{",
		indent
		+ "  hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::ArrayPayload>> "
		+ array
		+ "("
		+ heap
		+ ");",
		indent
		+ "  "
		+ heap
		+ ".allocateInto("
		+ array
		+ ", "
		+ CppManagedArrayRepresentation.select(type.getTypeArguments()[0], classes.casts)
		+ ");",
		indent + "  " + destination + ".set(hxhx::managed::Value::managed(" + array + ".get()));",
		indent + "}"
	];
}
