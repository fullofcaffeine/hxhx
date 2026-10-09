/** Compiler-owned global bindings support authored host access and shared identity allocation. */
class Main {
	static function main():Void {
		// These declared features are the protocol used by the real js.Lib provider.
		final marker:String = untyped __define_feature__("js.Lib.global", js.Syntax.code("$global.marker"));
		if (marker != "chosen")
			throw "wrong global host";
		#if uid
		final id:Int = untyped __define_feature__("$global.$haxeUID", js.Syntax.code("$global.$haxeUID++"));
		js.Syntax.code("$global.ids.push({0})", id);
		#end
	}
}
