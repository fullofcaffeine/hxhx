/** Static function values keep declaration identity, mutable callback order, and native print operands. */
class M14NekoStaticCallableValueTest {
	static function main():Void {
		// These programs use no library declarations; the direct fixture has their complete provider graph.
		@:privateAccess M14NekoClosureControlTest.assertSource("static_callable_values", 'class Provider {
public static function value(v:Int):Int return v+1;
public static dynamic function replaceable(v:Int):Int return 7;
}
typedef Alias=Provider;
class Main {
static function main():Void {
var first=Alias.value;
if(first!=Provider.value || first(2)!=3) throw "static function identity or invocation changed";
if(Alias.replaceable({Alias.replaceable=function(v:Int):Int return 9;1;})!=7) throw "dynamic callee was not captured first";
if(Alias.replaceable(1)!=9) throw "dynamic method replacement was lost";
var Provider={value:function(v:Int):Int {return v+10;}};
if(Provider.value(2)!=12) throw "local field was mistaken for a static declaration";
}
}', "");
		@:privateAccess M14NekoClosureControlTest.assertSource("native_print_operands", 'class Main {
static var events:String="";
static function mark(value:String):String {events+=value;return value;}
static function main():Void {
untyped __dollar__print(mark("L"),mark("R"),"\\n");
if(events!="LR") throw "native print changed operand order or count";
}
}', "LR\n");
	}
}
