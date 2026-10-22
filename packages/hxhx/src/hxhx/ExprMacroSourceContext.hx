package hxhx;

/**
	Original source ownership for a pre-typing syntax callback.
	The traversal supplies the exact class declaration and a private copy of its
	module directives. It does not load declarations or resolve written types.
	A declaration-selecting caller must bind sourceClass through its prepared
	request index/loader before calling the selector; short-name lookup is unsafe.
**/
typedef ExprMacroSourceContext = {
	final filePath:String;
	final modulePath:String;
	final packagePath:String;
	final directives:Array<HxModuleDirective>;
	final sourceClass:HxClassDecl;
}
