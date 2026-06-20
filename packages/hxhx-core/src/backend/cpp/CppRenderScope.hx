package backend.cpp;

typedef CppRenderScope = {
	var owner:Null<HxClassDecl>;
	var classNames:haxe.ds.StringMap<Bool>;
	var classByName:haxe.ds.StringMap<HxClassDecl>;
	var localTypes:haxe.ds.StringMap<String>;
	var argTypeOverrides:haxe.ds.StringMap<String>;
	var returnType:String;
}
