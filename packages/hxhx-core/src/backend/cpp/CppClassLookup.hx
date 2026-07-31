package backend.cpp;

typedef CppRenderedClassName = {
	var cls:HxClassDecl;
	var name:String;
}

typedef CppClassInfo = {
	var cls:HxClassDecl;
	var packagePath:String;
	var sourcePath:String;
}

typedef CppClassLookup = {
	var names:haxe.ds.StringMap<Bool>;
	var byName:haxe.ds.StringMap<HxClassDecl>;

	/**
		Request-owned declared-type results shared by scopes for this program.

		Ad-hoc lookup fixtures may omit this field; `CppTargetCore.renderScope`
		creates it before rendering begins.
	**/
	@:optional var declaredTypeMemo:CppDeclaredTypeMemo;

	/**
		Request-owned recursive function-analysis state shared by this program's
		render scopes.
	**/
	@:optional var functionAnalysisMemo:CppFunctionAnalysisMemo;

	/**
		Program-owned timing configuration and nested diagnostic buffer.
	**/
	@:optional var traceContext:CppTraceContext;

	@:optional var all:Array<HxClassDecl>;
	@:optional var renderedNames:Array<CppRenderedClassName>;
	@:optional var classInfos:Array<CppClassInfo>;
	@:optional var renderedNameByClass:haxe.ds.ObjectMap<HxClassDecl, String>;
	@:optional var packagePathByClass:haxe.ds.ObjectMap<HxClassDecl, String>;
	@:optional var sourcePathByClass:haxe.ds.ObjectMap<HxClassDecl, String>;
	@:optional var packageByRenderedName:haxe.ds.StringMap<String>;
	@:optional var helperRenderKindByClass:haxe.ds.ObjectMap<HxClassDecl, String>;
}
