package backend.cpp;

typedef CppRenderScope = {
	var owner:Null<HxClassDecl>;
	var classNames:haxe.ds.StringMap<Bool>;
	var classByName:haxe.ds.StringMap<HxClassDecl>;
	var localTypes:haxe.ds.StringMap<String>;
	var localNames:haxe.ds.StringMap<String>;
	var localNameCounts:haxe.ds.StringMap<Int>;
	var argTypeOverrides:haxe.ds.StringMap<String>;
	var returnType:String;
}
