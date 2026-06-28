package backend.cpp;

typedef CppRenderedClassName = {
	var cls:HxClassDecl;
	var name:String;
}

typedef CppClassLookup = {
	var names:haxe.ds.StringMap<Bool>;
	var byName:haxe.ds.StringMap<HxClassDecl>;
	@:optional var all:Array<HxClassDecl>;
	@:optional var renderedNames:Array<CppRenderedClassName>;
	@:optional var packageByRenderedName:haxe.ds.StringMap<String>;
}
