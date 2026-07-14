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
	var allClasses:Array<HxClassDecl>;
	@:optional var classLookup:CppClassLookup;

	/** Immutable class-graph inheritance results reused throughout one render scope. **/
	var classInheritanceCache:haxe.ds.StringMap<Bool>;

	/** Direct method owners already resolved in this scope's immutable class graph. **/
	var methodOwnerCache:haxe.ds.StringMap<HxClassDecl>;

	/** Direct method names proven absent from this scope's immutable class graph. **/
	var missingMethodOwnerCache:haxe.ds.StringMap<Bool>;

	/** Whether the nearest-owner cache has indexed the complete reachable owner chain. **/
	var methodOwnerGraphComplete:Bool;

	/**
		Nearest same-base class declarations already resolved relative to this owner.

		Unqualified type hints can have several module-local declarations with the
		same short name. The class graph and owner position are immutable for one
		render scope, so their nearest result can be shared by every type question
		asked while rendering that method.
	**/
	var nearestClassByBaseNameCache:haxe.ds.StringMap<HxClassDecl>;

	/** Same-base names proven absent from this scope's immutable class graph. **/
	var missingNearestClassByBaseNameCache:haxe.ds.StringMap<Bool>;

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
	var returnOnlyTypeParamAuto:Bool;
	@:optional var traceOwnerName:String;
	@:optional var traceMethodName:String;
	@:optional var traceStmtIndex:Int;
}
