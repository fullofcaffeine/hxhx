package backend.js;

typedef JsEmitScope = {
	final resolveLocal:String->Null<String>;
	final resolveClassRef:String->Null<String>;
	final resolveSuperClassRef:Void->Null<String>;
	final ?runtimeTypes:JsRuntimeTypeScope;
	final ?methodUses:HxExpr->Null<TypedBackendMethodOccurrence>;
	final ?lambdaUses:HxExpr->Null<TypedBackendLambdaOccurrence>;

	/** Authorize only original lowered operations from the current executable projection. */
	final ?requireExpression:HxExpr->Void;

	/** Abstract bodies read their backing value through this; ordinary classes read the instance. */
	final ?abstractReceiver:Bool;
};
