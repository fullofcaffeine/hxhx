package backend.vm;

import haxe.ds.StringMap;

/**
	Select shared Neko cells from exact typed capture dependencies.

	Neko copies lexical values into closures. A one-element native array gives
	all closures the same writable location. Projected names only locate cells
	after the typed catalog proves their declaration identity and creation event.
**/
class NekoCaptureStorage {
	final cells = new StringMap<TypedCaptureBinding>();
	final catalog:Null<TypedBackendCaptureCatalog>;

	public static function forFunction(projection:TypedBackendFunctionProjection):NekoCaptureStorage {
		var hasClosures = false;
		for (statement in projection.getBody())
			TypedBackendSourceWalk.statement(statement, expression -> {
				if (expression.match(ELambda(_, _)))
					hasClosures = true;
			}, _ -> {});
		return new NekoCaptureStorage(hasClosures ? projection.requireCaptureCatalog() : null, projection.getLocalCatalog());
	}

	/** Initializer closures share cells only within their own field-owned capture plan. */
	public static function forInitializer(projection:TypedBackendFieldInitializerProjection):NekoCaptureStorage {
		var hasClosures = false;
		TypedBackendSourceWalk.expression(projection.getExpression(), expression -> {
			if (expression.match(ELambda(_, _)))
				hasClosures = true;
		});
		return new NekoCaptureStorage(hasClosures ? projection.requireCaptureCatalog() : null, projection.getLocalCatalog());
	}

	function new(catalog:Null<TypedBackendCaptureCatalog>, locals:TypedBackendLocalCatalog) {
		this.catalog = catalog;
		if (catalog == null)
			return;
		final facts = catalog.getPlan();
		final captured = new StringMap<Bool>();
		for (fn in facts.getFunctions())
			for (binding in fn.getCaptures())
				captured.set(binding.getCanonicalIdentity(), true);
		for (source in facts.getBindings())
			if (captured.exists(source.binding.getCanonicalIdentity())) {
				final name = locals.projectedName(source.binding);
				if (cells.exists(name))
					throw "Neko capture storage repeats a projected binding";
				cells.set(name, source);
			}
	}

	/** Reject copied or foreign closure syntax before relying on its capture plan. */
	public function requireClosure(expression:HxExpr):Void {
		if (catalog == null)
			throw "Neko closure lacks its exact capture catalog";
		catalog.require(expression);
	}

	public function contains(name:String):Bool
		return cells.exists(name);

	/** Allocate at the authored declaration event, never when a closure merely reads it. */
	public function initialize(name:String, value:String):String
		return contains(name) ? "$array(" + value + ")" : value;

	/** Parameters get fresh storage on every invocation, after defaults are evaluated. */
	public function parameters(names:Array<String>, identifier:String->String):Array<String> {
		final result = new Array<String>();
		for (name in names)
			if (contains(name)) {
				if (cells.get(name).creation != FunctionEntry)
					throw "Neko parameter storage requires a function-entry binding";
				final emitted = identifier(name);
				result.push(emitted + " = $array(" + emitted + ");");
			}
		return result;
	}
}
