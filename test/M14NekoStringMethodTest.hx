/** Literal strings must support ordinary method calls and extracted method values. */
class M14NekoStringMethodTest {
	/** Resolve the real Array declarations and execute both Neko layouts against upstream. */
	static function assertSource(name:String, source:String, expected:String):Void {
		final root = ".tmp/neko_string_method_" + name + "_" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent(root + "/Main.hx", source);
		sys.io.File.saveContent(root + "/expected.stdout", expected);
		NekoRuntimeFixture.exercise(root, false);
	}

	static function main():Void {
		assertSource("string_methods", 'class Main {
static function main():Void {
var value="left:right";
var pieces=value.split(":");
Sys.println(pieces.length);Sys.println(pieces[0]);Sys.println(pieces[1]);
var split=value.split;
var saved=split(":");Sys.println(saved[0]);Sys.println(saved[1]);
Sys.println(Type.getClass(pieces)==Array);Sys.println(Type.getClass(saved)==Array);
var alias=pieces;Sys.println(pieces.push("tail"));Sys.println(alias[2]);Sys.println(saved.length);
}}', "2\nleft\nright\nleft\nright\ntrue\ntrue\n3\ntail\n2\n");
		assertSource("string_split_edges", 'class Main {
static function main():Void {
var adjacent=":a::b:".split(":");Sys.println(adjacent.length);Sys.println(adjacent.join("|"));
var absent="abc".split(":");Sys.println(absent.length);Sys.println(absent[0]);
var empty="".split(":");Sys.println(empty.length);Sys.println(empty.join("|"));
var characters="ab".split("");Sys.println(characters.length);Sys.println(characters.join("|"));
var bothEmpty="".split("");Sys.println(bothEmpty.length);Sys.println(bothEmpty.join("|"));
var events="";
function receiver():String {events+="receiver;";return "a:b";}
function argument():String {events+="argument;";return ":";}
var direct=receiver().split(argument());Sys.println(direct.join("|"));Sys.println(events);
events="";var saved=receiver().split;Sys.println(events);
events="";var later=saved(argument());Sys.println(later.join("|"));Sys.println(events);
var object={split:function(separator:String):Array<String>{return [separator,"object"];}};
Sys.println(object.split("!").join("|"));
}}',
			"5\n|a||b|\n1\nabc\n1\n\n2\na|b\n1\n\na|b\nreceiver;argument;\nreceiver;\na|b\nargument;\n!|object\n");
	}
}
