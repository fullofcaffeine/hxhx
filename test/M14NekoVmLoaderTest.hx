/** Reserved Neko loader reads retain their meaning even when local projection renames a binding. */
class M14NekoVmLoaderTest {
	static function main():Void {
		@:privateAccess M14NekoClosureControlTest.assertSource("vm_loader", 'class Main {
static var calls = 0;
static function loaderValue():Dynamic { calls++; return untyped __dollar__loader; }
static function read():Bool { return untyped __dollar__loader != null; }
static function platform():Bool { var symbol = "std@sys_string"; return untyped loaderValue().loadprim(symbol.__s, 0)() != null; }
static function shadow(__dollar__loader:Int):Dynamic { return __dollar__loader; }
static function main():Void {
var original:Dynamic = untyped __dollar__loader;
Sys.println(read());
Sys.println(platform());
Sys.println(calls);
Sys.println(shadow(7) == original);
var __dollar__loader = 9;
Sys.println((cast __dollar__loader:Dynamic) == original);
{ var __dollar__loader = 11; Sys.println((cast __dollar__loader:Dynamic) == original); }
var loader = 13;
Sys.println(loader);
var object = {run:function(value:Int):Int {return value+1;}};
Sys.println(object.run(4));
var missing:Dynamic = null;
var effects = 0;
try { missing.run(effects = effects + 1); } catch (error:Dynamic) {}
Sys.println(effects);
	}
}', "true\ntrue\n1\ntrue\ntrue\ntrue\n13\n5\n1\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("field_call_order", 'class Main {
static function main():Void {
var events="";
var object={run:function(value:Int):Int{return value+1;}};
function receiver() {events+="receiver;";return object;}
function argument():Int {
events+="argument;";
object.run=function(value:Int):Int{return value+10;};
return 2;
}
var result=receiver().run(argument());Sys.println(result);Sys.println(events);
}}', "12\nreceiver;argument;\n");
	}
}
