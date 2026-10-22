package hxhx;

/** Declaration selection can use names only when source traversal proves their complete visibility. */
enum ExprMacroScopeVisibility {
	Known(names:Array<String>);
	Unavailable(reason:String);
}
