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
	@:optional var all:Array<HxClassDecl>;
	@:optional var renderedNames:Array<CppRenderedClassName>;
	@:optional var classInfos:Array<CppClassInfo>;
	@:optional var renderedNameByClass:haxe.ds.ObjectMap<HxClassDecl, String>;
	@:optional var packagePathByClass:haxe.ds.ObjectMap<HxClassDecl, String>;
	@:optional var sourcePathByClass:haxe.ds.ObjectMap<HxClassDecl, String>;
	@:optional var packageByRenderedName:haxe.ds.StringMap<String>;
	@:optional var helperRenderKindByClass:haxe.ds.ObjectMap<HxClassDecl, String>;
}
