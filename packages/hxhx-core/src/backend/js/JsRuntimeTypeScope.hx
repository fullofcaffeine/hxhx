package backend.js;

/** One executable's exact type operands and their validated JavaScript provider references. */
typedef JsRuntimeTypeScope = {
	final requireOccurrence:HxExpr->TypedBackendRuntimeTypeOccurrence;
	final reference:TypedRuntimeTypeTarget->String;
};
