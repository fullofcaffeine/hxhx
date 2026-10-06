/** Authored classes share the entry module exports even when generated code occupies several VM modules. */
class M14NekoVmExportsTest {
	static function main():Void {
		@:privateAccess M14NekoClosureControlTest.assertSource("vm_exports", 'class Other {
public static function read():Dynamic {return untyped __dollar__exports;}
public static function write():Void {untyped __dollar__exports.observer=7;}
}
class Main {
static function shadow(__dollar__exports:Int):Dynamic {return __dollar__exports;}
static function main():Void {
var original:Dynamic=untyped __dollar__exports;
Sys.println(original!=null);Sys.println(original==Other.read());
Sys.println(untyped __dollar__exports.__module!=null);
// The harness names entry files upstream/main/single; support modules contain _chunk.
var moduleName:Dynamic=untyped __dollar__loader.loadprim("std@module_name".__s,1)(__dollar__exports.__module);
Sys.println(untyped __dollar__sfind(moduleName,0,"_chunk".__s)==null);
Other.write();Sys.println(untyped __dollar__exports.observer);
Sys.println(shadow(11)==original);
var __dollar__exports=13;Sys.println((cast __dollar__exports:Dynamic)==original);
var exports=17;Sys.println(exports);
}}', "true\ntrue\ntrue\ntrue\n7\ntrue\ntrue\n17\n");
	}
}
