package backend.js;

/** Exact executable facts used to call internal abstract helpers without exposing their receiver records. */
typedef JsAbstractValueScope = {
	final isAbstractOwner:String->Bool;
	final constructorReference:HxExpr->Null<String>;
	final requireCall:HxExpr->TypedBackendInstanceCallOccurrence;
	final methodReference:TyDeclarationInfo->Null<String>;
};
