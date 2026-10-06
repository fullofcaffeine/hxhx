/** Native loops must preserve body-first execution, condition effects, and lexical control destinations. */
class M14NekoDoWhileTest {
	static function main():Void {
		@:privateAccess M14NekoClosureControlTest.assertSource("do_while_instance", 'class Counter {
var tests=0;
public function new() {}
function check(value:Int):Bool {tests++;return value<4;}
public function run():Void {
var value=0;var sum=0;
do {value++;if(value==2)continue;sum+=value;} while(check(value));
Sys.println(value);Sys.println(sum);Sys.println(tests);
}
public function stop():Void {
var value=0;tests=0;
do {value++;if(value==2)break;Sys.println(value);} while(check(value));
Sys.println(value);Sys.println(tests);
}
public function once():Int {var value=0;do {value++;} while(false);return value;}
public function nested():Int {var sum=0;var outer=0;do {outer++;var inner=0;do {inner++;if(inner==2)break;sum++;} while(inner<3);} while(outer<2);return sum;}
}
class Main {static function main():Void {var counter=new Counter();counter.run();counter.stop();Sys.println(counter.once());Sys.println(counter.nested());}}',
			"4\n8\n4\n1\n2\n1\n1\n2\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("do_while_closure", 'class Main {static function main():Void {
var call=function():Int {var value=0;do {value++;if(value==2)return value;} while(value<3);return -1;};
Sys.println(call());
var first:Void->Int=function():Int {return -1;};var second:Void->Int=first;var i=0;
do {var captured=i;var get=function():Int {captured++;return captured;};if(i==0)first=get;else second=get;i++;} while(i<2);
Sys.println(first());Sys.println(first());Sys.println(second());
}}', "2\n1\n2\n2\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("do_while_inner_try",
			'class Main {static var tests=0;static function check(value:Int):Bool {tests++;return value<8;} static function main():Void {
var value=0;
do {try {value++;if(value==2)continue;if(value==4)break;Sys.println(value);} catch(e:Dynamic) {Sys.println("caught");}} while(check(value));
Sys.println(value);Sys.println(tests);
}}', "1\n3\n4\n3\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("do_while_reachability",
			'class Box {public function new() {} public function read():Int {return 9;}}
class Helper {public static function check(value:Int):Bool {return value<1;}}
class Main {static function main():Void {var value=0;do {Sys.println(new Box().read());value++;} while(Helper.check(value));}}', "9\n");
	}
}
