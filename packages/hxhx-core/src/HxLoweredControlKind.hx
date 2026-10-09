/**
	Executable control selected by shared lowering after source typing.

	FunctionBody establishes the return destination. Scope preserves lexical lifetime.
	Return exits the named function region; it is never an implicit expression result.
	These tags carry no source syntax and cannot be exported to a macro as authored braces.
 */
enum HxLoweredControlKind {
	FunctionBody;

	/** Execute children in one initializer scope; only a marked final child supplies the field value. */
	Initializer(hasValue:Bool);

	Scope;
	TargetScope(kind:HxTargetScopeKind);
	Return;
	Branch;
	Throw;
	While(kind:HxWhileKind);
	For(binding:HxForBinding);

	/** Retain shared coverage through function and initializer statement adaptation. */
	Switch(patterns:Array<HxSwitchPattern>, ?exhaustive:Bool);

	Try(catches:Array<HxSourceCatch>);
	Break;
	Continue;

	/** Append one already selected element to an exact array value; no source method lookup remains. */
	ArrayAppend;

	MapInsert;
}
