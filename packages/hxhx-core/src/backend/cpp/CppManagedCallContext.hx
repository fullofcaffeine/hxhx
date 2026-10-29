package backend.cpp;

/** Class arguments come from the exact executable that owns a call, including its nested closures. */
enum CppManagedEnclosingApplication {
	FunctionBody(application:CppManagedFunctionApplication);
	FieldBody(application:CppManagedInitializerApplication);
}

/** Registration keeps source ownership independently of any later concrete application. */
enum CppManagedCallOwner {
	FunctionSource(projection:TypedBackendFunctionProjection);
	FieldSource(projection:TypedBackendFieldInitializerProjection);
}

/** Static and unapplied nongeneric bodies have no class substitution context. */
function fromFunction(application:Null<CppManagedFunctionApplication>):Null<CppManagedEnclosingApplication>
	return application == null ? null : FunctionBody(application);

/** Static fields have no instance application; instance fields retain their own class arguments. */
function fromInitializer(application:Null<CppManagedInitializerApplication>):Null<CppManagedEnclosingApplication>
	return application == null ? null : FieldBody(application);

/** Distinguish every concrete use of one lexical call when freezing virtual dispatch. */
function identity(context:Null<CppManagedEnclosingApplication>):String
	return switch context {
		case null: "";
		case FunctionBody(application): application.identity;
		case FieldBody(application): application.identity;
	};

/** A retained method plan must revalidate its enclosing application before reuse. */
function assertCurrent(context:Null<CppManagedEnclosingApplication>):Void {
	switch context {
		case null:
		case FunctionBody(application):
			application.assertCurrent();
		case FieldBody(application):
			application.assertCurrent();
	}
}

/** A constructor or equal source text cannot substitute for the field or method that owns the call. */
function assertOwner(context:Null<CppManagedEnclosingApplication>, owner:CppManagedCallOwner):Void {
	if (context == null)
		return;
	assertCurrent(context);
	switch [context, owner] {
		case [FunctionBody(application), FunctionSource(projection)] if (application.projection == projection):
		case [FieldBody(application), FieldSource(projection)] if (application.projection == projection):
		case _:
			throw "managed instance context belongs to another executable owner";
	}
}

/** Resolve semantic receiver/result types; the selected method separately determines native storage. */
function resolveType(context:Null<CppManagedEnclosingApplication>, type:TyType):TyType
	return switch context {
		case null: type;
		case FunctionBody(application): application.resolveType(type);
		case FieldBody(application): application.resolveType(type);
	};
