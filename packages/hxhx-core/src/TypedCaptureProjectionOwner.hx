/** Authored and lowered evidence for one real executable's projected capture occurrences. */
enum TypedCaptureProjectionOwner {
	FunctionBody(source:TypedFunction, lowered:TypedFunction, declaration:HxFunctionDecl);
	FieldInitializer(source:TypedFieldInitializer, lowered:TypedControlLowering.LoweredFieldInitializer, declaration:HxFieldDecl);
}
