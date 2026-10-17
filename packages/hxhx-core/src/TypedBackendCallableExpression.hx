/**
	A callback-related projected expression and the checked typed node that produced it.

	The owning capture catalog validates the complete typed and projected bodies
	before publishing this pair. A source position or equal spelling cannot replace
	that ownership. These facts describe the source; the target must still select
	callback storage, origin identity and argument/result conversions.
**/
typedef TypedBackendCallableExpression = {
	final expression:HxExpr;
	final source:TypedExpr;
};
