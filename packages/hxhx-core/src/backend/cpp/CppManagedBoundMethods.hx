package backend.cpp;

import backend.cpp.CppManagedCallContext.CppManagedEnclosingApplication;
import backend.cpp.CppManagedMethods.CppManagedInstanceDispatchCase;

/** One stored-method occurrence can execute under several concrete enclosing applications. */
typedef CppManagedBoundMethodUse = {
	final occurrence:TypedBackendMethodOccurrence;
	final context:Null<CppManagedEnclosingApplication>;
}

private typedef BoundMethodOwner = {
	final source:backend.cpp.CppManagedCallContext.CppManagedCallOwner;
	final find:Void->Null<TypedBackendMethodOccurrence>;
}

/**
	Retain exact stored-method selections through reachability and code generation.
	A stored method selects bodies before dispatch is sealed, just as a direct call
	does. Its original function or field owns the occurrence and type substitution;
	no fabricated call supplies argument facts that the source never had.
 */
class CppManagedBoundMethods {
	final program:CppTypedProgramProjection;
	final classes:CppManagedClassStorage;
	final methods:CppManagedMethods;
	final owners = new haxe.ds.ObjectMap<TypedBackendMethodOccurrence, BoundMethodOwner>();
	var sealed:Null<haxe.ds.ObjectMap<TypedBackendMethodOccurrence, haxe.ds.StringMap<Array<CppManagedInstanceDispatchCase>>>>;

	public function new(program:CppTypedProgramProjection, classes:CppManagedClassStorage, methods:CppManagedMethods) {
		this.program = program;
		this.classes = classes;
		this.methods = methods;
	}

	/** Discover values only; calls and dynamic-method writes keep their existing owners. */
	public function functionValue(projection:TypedBackendFunctionProjection, expression:HxExpr):Null<TypedBackendMethodOccurrence> {
		if (!expression.match(EField(_, _)))
			return null;
		final occurrence = projection.findMethodUse(expression);
		if (occurrence == null || occurrence.getUse() != ValueRead)
			return null;
		classes.assertFunction(projection);
		owners.set(occurrence, {source: FunctionSource(projection), find: () -> projection.findMethodUse(expression)});
		return occurrence;
	}

	public function initializerValue(projection:TypedBackendFieldInitializerProjection, expression:HxExpr):Null<TypedBackendMethodOccurrence> {
		if (!expression.match(EField(_, _)))
			return null;
		final occurrence = projection.findMethodUse(expression);
		if (occurrence == null || occurrence.getUse() != ValueRead)
			return null;
		classes.assertInitializer(projection);
		owners.set(occurrence, {source: FieldSource(projection), find: () -> projection.findMethodUse(expression)});
		return occurrence;
	}

	/** Revalidate exact source ownership before applying any enclosing generic arguments. */
	public function application(occurrence:TypedBackendMethodOccurrence, context:Null<CppManagedEnclosingApplication>):CppManagedFunctionApplication {
		program.assertCurrent();
		final owner = owners.get(occurrence);
		if (owner == null || owner.find() != occurrence || occurrence.getUse() != ValueRead)
			throw "managed bound method belongs to another program or occurrence";
		CppManagedCallContext.assertOwner(context, owner.source);
		final declaration = occurrence.getDeclaration();
		final receiver = CppManagedCallContext.resolveType(context, occurrence.getReceiverType());
		if (receiver.getNominalIdentity() == null)
			throw "managed bound method requires its exact receiver ancestry";
		final selectedOwner = program.requireClass(program.requireClassIdentity(declaration.getOwner().getCanonicalName()));
		final matches = selectedOwner.getFunctions().filter(fn -> fn.requireSemanticDeclaration() == declaration);
		if (matches.length != 1)
			throw "managed bound method lacks its exact program declaration";
		// The shared method planner validates the exact applied receiver ancestry.
		final selected = methods.ordinaryMethodApplication(matches[0], receiver, () -> {
			if (owner.find() != occurrence)
				throw "managed bound method occurrence changed";
			CppManagedCallContext.assertOwner(context, owner.source);
		});
		final signature = CppManagedFunctionSignature.resolve(selected.projection, selected.resolveType);
		if (signature.getSemanticKey() != CppManagedCallContext.resolveType(context, occurrence.getCallableType()).getSemanticKey())
			throw "managed bound method requires its exact applied callable signature";
		return selected;
	}

	/** Query while discovering bodies, then use only the frozen allocation set during rendering. */
	public function dispatch(occurrence:TypedBackendMethodOccurrence, context:Null<CppManagedEnclosingApplication>):Array<CppManagedInstanceDispatchCase> {
		final selected = application(occurrence, context);
		if (sealed == null)
			return methods.dispatchApplication(selected, CppManagedCallContext.resolveType(context, occurrence.getReceiverType()));
		final uses = sealed.get(occurrence);
		final cases = uses == null ? null : uses.get(CppManagedCallContext.identity(context));
		if (cases == null)
			throw "managed bound method is absent from sealed dispatch";
		for (entry in cases)
			entry.application.assertCurrent();
		return [
			for (entry in cases)
				{descriptor: entry.descriptor, application: entry.application}
		];
	}

	/** Called once after both direct-call and method-value reachability reach the same fixed point. */
	public function seal(uses:Array<CppManagedBoundMethodUse>):Void {
		if (sealed != null)
			throw "managed bound method dispatch was already sealed";
		final result = new haxe.ds.ObjectMap<TypedBackendMethodOccurrence, haxe.ds.StringMap<Array<CppManagedInstanceDispatchCase>>>();
		for (use in uses) {
			var entries = result.get(use.occurrence);
			if (entries == null) {
				entries = new haxe.ds.StringMap();
				result.set(use.occurrence, entries);
			}
			entries.set(CppManagedCallContext.identity(use.context), dispatch(use.occurrence, use.context));
		}
		sealed = result;
	}
}
