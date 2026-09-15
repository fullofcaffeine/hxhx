package backend.vm;

import haxe.ds.StringMap;
import backend.vm.NekoTypedProgramProjection.NekoProjectedFunction;

/** One exact projected class and its target naming context. */
typedef NekoClassInfo = {
	var fullName:String;
	var shortName:String;
	var cls:HxClassDecl;
}

/** Request-local Neko emission state; child scopes retain the exact program and class graph. */
typedef NekoEmitContext = {
	var classes:StringMap<NekoClassInfo>;
	var typedProgram:NekoTypedProgramProjection;

	/** Exact enclosing function; null only for code outside a projected function body. */
	var currentFunction:Null<NekoProjectedFunction>;

	var abstractHelpers:Array<NekoProjectedFunction>;
	var abstractHelperIds:StringMap<Bool>;
	var directAbstractReceiver:Bool;
	var selfName:Null<String>;
	var currentClass:Null<NekoClassInfo>;
	var symbolTable:Null<String>;
	var packFunctionArguments:Bool;
	var locals:StringMap<Bool>;
	var insideTry:Bool;
	var breakFlag:Null<String>;
}
