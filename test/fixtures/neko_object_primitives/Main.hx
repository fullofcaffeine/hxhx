/** Reserved VM aliases keep their native meaning even when typed locals share their names. */
class Main {
	static function main():Void {
		var __dollar__typeof = function(value:{value:Int}):Int return 101;
		var __dollar__tobject = 99;
		// The untyped boundary selects native VM operations; each result is checked immediately.
		Sys.println(untyped __dollar__typeof({value: 0}) == __dollar__tobject);
		final box = {value: 0};
		var __dollar__objset = function(object:{value:Int}, field:Int, value:Int):Int return 103;
		untyped __dollar__objset(box, __dollar__hash("value".__s), 7);
		Sys.println(box.value);
	}
}
