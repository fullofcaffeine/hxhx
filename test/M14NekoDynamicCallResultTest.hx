/** Dynamic function results reach typed arguments with identical upstream and generated Neko evaluation order. */
class M14NekoDynamicCallResultTest {
	/** Load real library declarations before comparing upstream and both generated Neko layouts. */
	static function assertSource(name:String, source:String, expected:String):Void {
		final fixture = ".tmp/neko_dynamic_call_providers_" + name + "_" + Date.now().getTime();
		sys.FileSystem.createDirectory(fixture);
		sys.io.File.saveContent(fixture + "/Main.hx", source);
		sys.io.File.saveContent(fixture + "/expected.stdout", expected);
		NekoRuntimeFixture.exercise(fixture, false);
	}

	static function main():Void {
		assertSource("dynamic_call_result", 'class Main {
static var events:String="";
static function acquire():Dynamic {events+="c";return function(value:Int):String {events+="f";return "word";};}
static function argument():Int {events+="a";return 7;}
static function take(value:String):String {events+="r";return value;}
static function main():Void {
Sys.println(take(acquire()(argument())));
Sys.println(events);
var callback:Dynamic=acquire();
Sys.println(take(callback(argument())));
Sys.println(events);
}
}', "word\ncafr\nword\ncafrcafr\n");
		// The declared String observer complements direct Dynamic Sys.println arguments below.
		assertSource("dynamic_call_declared_observer", 'class Main {
static var selected:Dynamic;
static function first(value:Int):String {return "first";}
static function second(value:Int):String {return "second";}
static function replace():Int {selected=second;return 1;}
static function acquire():Dynamic {return selected;}
static function observe(value:String):Void {Sys.println(value);}
static function main():Void {
selected=first;observe(selected(replace()));
selected=first;observe(Main.selected(replace()));
var callback:Dynamic=first;observe(callback({callback=second;1;}));
var record={call:first};observe(record.call({record.call=second;1;}));
selected=first;observe((if (true) acquire() else selected)(replace()));
var __hxhx_call_value="reserved";observe(__hxhx_call_value);
}
}', "first\nfirst\nfirst\nfirst\nfirst\nreserved\n");
		assertSource("dynamic_call_capture", 'class Main {
static var selected:Dynamic;
static function first(value:Int):String {return "first";}
static function second(value:Int):String {return "second";}
static function replace():Int {selected=second;return 1;}
static function acquire():Dynamic {return selected;}
static function main():Void {
selected=first;Sys.println(selected(replace()));
selected=first;Sys.println(Main.selected(replace()));
var callback:Dynamic=first;Sys.println(callback({callback=second;1;}));
var record={call:first};Sys.println(record.call({record.call=second;1;}));
selected=first;Sys.println((if (true) acquire() else selected)(replace()));
var __hxhx_call_value="reserved";Sys.println(__hxhx_call_value);
}
}', "first\nfirst\nfirst\nfirst\nfirst\nreserved\n");
	}
}
