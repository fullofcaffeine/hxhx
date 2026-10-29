package backend.js;

/**
	Select mutable cells for repeated captured declarations, loop bindings, and patterns.
	A declaration inside a loop or guard can execute repeatedly, even when its
	typed creation event is Declaration. Each execution creates a new cell;
	closures from that execution share it and retain it after the next execution.
	Parameters and declarations that cannot repeat retain native JavaScript sharing.
	This also preserves the shared program scope of class startup declarations.
 */
class JsIterationCaptureStorage {
	final catalog:Void->TypedBackendCaptureCatalog;
	final locals:TypedBackendLocalCatalog;
	final names:haxe.ds.StringMap<Bool> = new haxe.ds.StringMap();
	var prepared:Bool = false;

	public function new(catalog:Void->TypedBackendCaptureCatalog, locals:TypedBackendLocalCatalog) {
		this.catalog = catalog;
		this.locals = locals;
	}

	function prepare():Void {
		if (prepared)
			return;
		final plan = catalog().getPlan();
		final captured = new haxe.ds.StringMap<Bool>();
		for (fn in plan.getFunctions())
			for (binding in fn.getCaptures())
				captured.set(binding.getCanonicalIdentity(), true);
		for (fact in plan.getBindings())
			if (((fact.creation == Declaration && fact.isRepeated) || fact.creation == LoopIteration || fact.creation == PatternMatch)
				&& captured.exists(fact.binding.getCanonicalIdentity()))
				names.set(locals.projectedName(fact.binding), true);
		prepared = true;
	}

	/** Transport names come from the owning local catalog, never from authored spelling. */
	public function isCaptured(name:String):Bool {
		prepare();
		return names.exists(name);
	}

	/** Exact closure lookup includes captures forwarded to descendants. */
	public function captures(expression:HxExpr):Array<String> {
		prepare();
		return [
			for (binding in catalog().require(expression).getCaptures()) {
				final name = locals.projectedName(binding);
				if (names.exists(name)) name;
			}
		];
	}
}
