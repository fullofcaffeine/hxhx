package backend.cpp;

/** An executable entry always names a concrete authored method body. */
typedef CppManagedInstanceMethodEntry = {
	final projection:TypedBackendFunctionProjection;
	final symbol:String;
	final application:CppManagedFunctionApplication;
}

/**
	A call contract selects a direct body or reachable allocation cases.
	Interface signatures have no direct entry and do not acquire a fake symbol.
 */
typedef CppManagedInstanceMethodTarget = {
	final projection:TypedBackendFunctionProjection;
	final application:CppManagedFunctionApplication;
	final entry:Null<CppManagedInstanceMethodEntry>;
	final dispatch:Null<Array<{final descriptor:String; final target:CppManagedInstanceMethodEntry;}>>;
}

/** A checked occurrence selects its exact method; source spelling and copied declarations cannot. */
function select(program:CppTypedProgramProjection, call:TypedBackendInstanceCallOccurrence, methods:CppManagedMethods,
		receiver:TyType):TypedBackendFunctionProjection {
	final declaration = call.getDeclaration();
	methods.assertInstanceReceiver(call, receiver);
	final owner = program.requireClass(program.requireClassIdentity(declaration.getOwner().getCanonicalName()));
	for (projection in owner.getFunctions()) {
		if (projection.requireSemanticDeclaration() != declaration)
			continue;
		methods.assertInstanceMethod(projection);
		return projection;
	}
	throw 'managed instance method lacks its exact program declaration';
}
