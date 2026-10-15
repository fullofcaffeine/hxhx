package backend.js;

typedef JsEmitScope = {
	final resolveLocal:String->Null<String>;
	final resolveClassRef:String->Null<String>;
	final resolveSuperClassRef:Void->Null<String>;
	final ?runtimeTypes:JsRuntimeTypeScope;
	final ?abstractValues:JsAbstractValueScope;

	/** Exact retained enum declarations for target-owned quotation construction. */
	final ?enumDeclarations:String->JsClassInheritancePlan.JsClassInheritanceNode;

	final ?methodUses:HxExpr->Null<TypedBackendMethodOccurrence>;
	final ?lambdaUses:HxExpr->Null<TypedBackendLambdaOccurrence>;
	final ?iterationStorage:JsIterationCaptureStorage;
	final ?resolveIterationCell:String->Null<String>;

	/** Exact typed function values, including static extern methods saved before argument effects. */
	final ?callableExpressions:HxExpr->Null<TypedExpr>;

	/** Authorize only original lowered operations from the current executable projection. */
	final ?requireExpression:HxExpr->Void;

	/** Abstract bodies read their backing value through this; ordinary classes read the instance. */
	final ?abstractReceiver:Bool;
};
