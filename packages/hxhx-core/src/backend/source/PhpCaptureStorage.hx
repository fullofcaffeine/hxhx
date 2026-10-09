package backend.source;

import haxe.ds.StringMap;

/**
	Select PHP reference captures from exact typed declaration identities.

	PHP closures share a referenced variable's storage. Unsetting the local
	name before a repeated declaration detaches the old storage without changing
	closures that retained it. Parameters already get fresh storage per call.
	Loop headers use a distinct carrier so they cannot overwrite an earlier
	iteration's captured variable before the new binding is created.
**/
class PhpCaptureStorage {
	final catalog:Null<TypedBackendCaptureCatalog>;
	final locals:TypedBackendLocalCatalog;
	final captured = new StringMap<TypedCaptureBinding>();
	final carriers = new StringMap<String>();

	public static function forFunction(projection:TypedBackendFunctionProjection):PhpCaptureStorage {
		var found = false;
		for (statement in projection.getBody())
			TypedBackendSourceWalk.statement(statement, value -> {
				if (value.match(ELambda(_, _)))
					found = true;
			}, _ -> {});
		return new PhpCaptureStorage(found ? projection.requireCaptureCatalog() : null, projection.getLocalCatalog());
	}

	public static function forInitializer(projection:TypedBackendFieldInitializerProjection):PhpCaptureStorage {
		var found = false;
		TypedBackendSourceWalk.expression(projection.getExpression(), value -> {
			if (value.match(ELambda(_, _)))
				found = true;
		});
		return new PhpCaptureStorage(found ? projection.requireCaptureCatalog() : null, projection.getLocalCatalog());
	}

	function new(catalog:Null<TypedBackendCaptureCatalog>, locals:TypedBackendLocalCatalog) {
		this.catalog = catalog;
		this.locals = locals;
		if (catalog == null)
			return;
		final plan = catalog.getPlan();
		final identities = new StringMap<Bool>();
		for (fn in plan.getFunctions())
			for (binding in fn.getCaptures())
				identities.set(binding.getCanonicalIdentity(), true);
		final reserved = new StringMap<Bool>();
		for (local in locals.getEntries())
			reserved.set(PhpName.valueIdentifier(local.getProjectedName()), true);
		var next = 0;
		for (entry in plan.getBindings())
			if (identities.exists(entry.binding.getCanonicalIdentity())) {
				final name = PhpName.valueIdentifier(locals.projectedName(entry.binding));
				if (captured.exists(name))
					throw "PHP capture storage repeats one target binding";
				captured.set(name, entry);
				var carrier:String;
				do {
					carrier = "__hxhx_capture_iteration_" + next++;
				} while (reserved.exists(carrier));
				reserved.set(carrier, true);
				carriers.set(name, carrier);
			}
	}

	/** Authorize the original occurrence before any PHP expression rewrite copies it. */
	public function requireClosure(expression:HxExpr):TypedCaptureFunction {
		if (catalog == null)
			throw "PHP closure lacks an exact capture catalog";
		return catalog.require(expression);
	}

	public function captureNames(expression:HxExpr):Array<String>
		return [
			for (binding in requireClosure(expression).getCaptures())
				PhpName.valueIdentifier(locals.projectedName(binding))
		];

	public function hasClosures():Bool
		return catalog != null;

	public function contains(name:String):Bool
		return captured.exists(PhpName.valueIdentifier(name));

	/** Preserve old captured storage while giving this declaration a fresh PHP variable. */
	public function renewal(name:String, indent:String):Array<String>
		return contains(name) ? [indent + "unset($" + PhpName.valueIdentifier(name) + ");"] : [];

	public function iterationCarrier(name:String):String {
		final target = PhpName.valueIdentifier(name);
		return captured.exists(target) ? carriers.get(target) : target;
	}
}
