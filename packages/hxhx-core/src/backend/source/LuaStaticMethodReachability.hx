package backend.source;

import backend.source.LuaClassPlan.LuaClassOwner;
import haxe.ds.StringMap;

/**
	Retain the entry class's executable static helpers by exact declaration identity.
	Other class APIs and all instance methods remain roots. Field initializers,
	captured static method values, and transitive calls also retain their targets.
	Runtime type operands conservatively retain every entry helper because they
	can expose class members indirectly. This is not a whole-program DCE pass.
**/
class LuaStaticMethodReachability {
	final functions:StringMap<TypedBackendFunctionProjection> = new StringMap();
	final selected:StringMap<Bool> = new StringMap();
	final queue:Array<TypedBackendFunctionProjection> = [];

	public function new(classes:Array<LuaClassOwner>, main:TypedBackendClassProjection) {
		for (owner in classes)
			for (fn in owner.projection.getFunctions())
				functions.set(fn.getStableIdentity(), fn);
		function retainAll():Void {
			for (fn in functions)
				retain(fn.getStableIdentity());
		}
		for (owner in classes) {
			for (fn in owner.projection.getFunctions()) {
				final declaration = fn.getDeclaration();
				final metadata = HxFunctionDecl.getMetadata(declaration);
				if (owner.projection != main
					|| !HxFunctionDecl.getIsStatic(declaration)
					|| HxFunctionDecl.getName(declaration) == "main"
					|| metadata.indexOf("keep") >= 0
					|| metadata.indexOf("expose") >= 0)
					retain(fn.getStableIdentity());
			}
			for (initializer in owner.projection.getFieldInitializers()) {
				initializer.requireCaptureCatalog().assertCurrent();
				if (initializer.getRuntimeTypeCatalog().getEntries().length != 0)
					retainAll();
				TypedBackendSourceWalk.expression(initializer.getExpression(),
					expression -> observe(expression, initializer.findCallableExpression(expression)));
			}
		}
		var next = 0;
		while (next < queue.length) {
			final fn = queue[next++];
			fn.requireCaptureCatalog().assertCurrent();
			if (fn.getRuntimeTypeCatalog().getEntries().length != 0)
				retainAll();
			TypedBackendSourceWalk.functionDeclaration(fn.getDeclaration(), expression -> observe(expression, fn.findCallableExpression(expression)), _ -> {});
		}
	}

	function retain(identity:String):Void {
		if (selected.exists(identity))
			return;
		final fn = functions.get(identity);
		if (fn != null) {
			selected.set(identity, true);
			queue.push(fn);
		}
	}

	/** The original nodes are visited only after their executable's complete freshness check. */
	function observe(expression:HxExpr, callable:Null<TypedExpr>):Void {
		final call = TypedExactStaticCallSource.decode(expression);
		if (call != null)
			retain(call.declaration);
		final declaration = callable == null ? null : callable.getDeclaration();
		if (declaration != null && declaration.getIsStatic())
			retain(declaration.getIdentity().getCanonicalKey());
	}

	public function includes(fn:TypedBackendFunctionProjection):Bool
		return selected.exists(fn.getStableIdentity());
}
