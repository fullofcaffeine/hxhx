package backend.cpp;

typedef CppClassLookup = {
	var names:haxe.ds.StringMap<Bool>;
	var byName:haxe.ds.StringMap<HxClassDecl>;
	@:optional var all:Array<HxClassDecl>;
}
