/** Enum calls must retain their declaration across payload construction, aliases, and reachability. */
class M14NekoExactEnumConstructorTest {
	static function main():Void {
		@:privateAccess M14NekoClosureControlTest.assertSource("optional_enum_constructor", 'enum Item {Value(number:Int,?text:String);}
class Main {
static function observe(value:Item):Void {switch(value) {case Value(number,text):Sys.println(number);Sys.println(text==null?"absent":text);}}
static function main():Void {observe(Item.Value(1));observe(Item.Value(2,"present"));observe(Item.Value(3,null));}
}', "1\nabsent\n2\npresent\n3\nabsent\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("generic_enum_constructor", 'enum Result<T> {Empty;Value(item:T);}
class Main {static function main():Void {var value=Result.Value(4);var text=Result.Value("text");switch(value) {case Empty:Sys.println(-1);case Value(item):Sys.println(item+1);}switch(text) {case Empty:Sys.println("empty");case Value(item):Sys.println(item.length);}}}',
			"5\n4\n");
		@:privateAccess M14NekoClosureControlTest.assertSource("exact_enum_constructor", 'enum Item {Empty;Pair(number:Int,text:String);Nested(value:Item);}
enum Other {Empty;Pair(number:Int,text:String);}
typedef Alias=Item;
class Main {
static var calls=0;
static function number():Int {calls++;return 3;}
static function text():String {calls++;return "value";}
static function observe(value:Item):Void {switch(value) {case Empty:Sys.println("empty");case Pair(number,text):Sys.println(number);Sys.println(text);case Nested(inner):observe(inner);}}
static function main():Void {
observe(Item.Empty);var pair=Alias.Pair(number(),text());observe(pair);Sys.println(calls);observe(Item.Nested(pair));
Sys.println(Item.Empty==Alias.Empty);Sys.println(pair==pair);var another=Item.Pair(3,"value");Sys.println(pair==another);
Sys.println((cast Item.Empty:Dynamic)==(cast Other.Empty:Dynamic));
}}', "empty\n3\nvalue\n2\n3\nvalue\ntrue\ntrue\nfalse\nfalse\n");
	}
}
