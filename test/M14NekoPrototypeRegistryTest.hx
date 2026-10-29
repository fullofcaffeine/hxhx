/** Class prototypes must remain shared by existing and inherited instances after source writes. */
class M14NekoPrototypeRegistryTest {
	static function main():Void {
		@:privateAccess M14NekoClosureControlTest.assertSource("prototype_getter", 'class Parent {
public var value(get,never):Int;
var stored:Int;
public function new(value:Int){stored=value;}
public function get_value():Int{return stored;}
}
class Child extends Parent {public function new(value:Int){super(value);}}
class Main {static function main():Void {
var first=new Child(7);var second=new Child(11);
Sys.println(first.value);Sys.println(second.value);
var calls=0;
function receiver():Child {calls++;return first;}
Sys.println(receiver().value);Sys.println(calls);
var saved=first.get_value;Sys.println(saved());
}}', "7\n11\n7\n1\n7\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("prototype_registry", 'class Parent {public function new(){}}
class Child extends Parent {public function new(){super();}}
class Main {static function main():Void {
untyped Parent.prototype.flag=7;
var first=new Child();Sys.println(untyped first.flag);
untyped Parent.prototype.flag=9;Sys.println(untyped first.flag);
untyped first.flag=11;Sys.println(untyped first.flag);
var second=new Child();Sys.println(untyped second.flag);
}}', "7\n9\n11\n9\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("prototype_methods", 'class Parent {
public var empty:Int;
public var initialized:Int=3;
public var explicitNull:Null<Int>=null;
public function new(){}
public function read():Int {return empty;}
public function nested():Void->Int {return function():Int{return empty;};}
}
class Child extends Parent {public function new(){super();}}
class Main {static function main():Void {
untyped Parent.prototype.empty=7;
untyped Parent.prototype.initialized=8;
untyped Parent.prototype.explicitNull=9;
var first=new Child();
Sys.println(first.empty);Sys.println(first.initialized);Sys.println(first.explicitNull);
Sys.println(first.read());
var saved=first.read;var nested=first.nested();
untyped Parent.prototype.empty=10;
Sys.println(first.empty);Sys.println(saved());Sys.println(nested());
untyped Parent.prototype.read=function():Int{return 40;};
Sys.println(first.read());Sys.println(saved());
var second=new Child();Sys.println(second.read());
first.empty=12;Sys.println(first.empty);Sys.println(second.empty);
Sys.println(saved());Sys.println(nested());
}}', "7\n3\nnull\n7\n10\n10\n10\n40\n10\n40\n12\n10\n12\n12\n");
	}
}
