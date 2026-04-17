package backend.js;

typedef JsEmitScope = {
	final resolveLocal:String->Null<String>;
	final resolveClassRef:String->Null<String>;
	final resolveSuperClassRef:Void->Null<String>;
};
