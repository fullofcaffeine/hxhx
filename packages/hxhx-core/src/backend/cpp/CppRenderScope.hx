package backend.cpp;

typedef CppScopeAnonStruct = {
	var name:String;
	var fieldNames:Array<String>;
	var fieldTypes:Array<String>;
}

typedef CppRenderScope = {
	var owner:Null<HxClassDecl>;
	var classNames:haxe.ds.StringMap<Bool>;
	var classByName:haxe.ds.StringMap<HxClassDecl>;
	var typeParams:Array<String>;
	var typeParamCppNames:haxe.ds.StringMap<String>;
	var localTypes:haxe.ds.StringMap<String>;
	var localTypeHints:haxe.ds.StringMap<String>;
	var localNames:haxe.ds.StringMap<String>;
	var localNameCounts:haxe.ds.StringMap<Int>;
	var argTypeOverrides:haxe.ds.StringMap<String>;
	var localTypeOverrides:haxe.ds.StringMap<String>;
	var anonStructs:haxe.ds.StringMap<CppScopeAnonStruct>;
	var returnType:String;
}
