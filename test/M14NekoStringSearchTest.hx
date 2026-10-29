/** Native string search preserves offsets, missing results, and argument evaluation order. */
class M14NekoStringSearchTest {
	static function main():Void {
		// Untyped values are confined to the explicit native Neko string boundary.
		@:privateAccess M14NekoClosureControlTest.assertSource("string_search", 'class Main {
static function main():Void {
Sys.println(untyped __dollar__sfind("ababa".__s,0,"ba".__s));
Sys.println(untyped __dollar__sfind("ababa".__s,2,"ba".__s));
Sys.println(untyped __dollar__sfind("ababa".__s,4,"ba".__s)==null);
var failed=false;
try {untyped __dollar__sfind("".__s,0,"x".__s);} catch(error:Dynamic) {failed=true;}
Sys.println(failed);
Sys.println(untyped __dollar__sfind("abc".__s,1,"".__s));
var events="";
function haystack():Dynamic {events+="h";return untyped "abc".__s;}
function offset():Int {events+="o";return 0;}
function needle():Dynamic {events+="n";return untyped "b".__s;}
Sys.println(untyped __dollar__sfind(haystack(),offset(),needle()));
Sys.println(events);
var object={__dollar__sfind:function():Int{return 9;}};
Sys.println(object.__dollar__sfind());
}}', "1\n3\ntrue\ntrue\n1\n1\nhon\n9\n");
	}
}
