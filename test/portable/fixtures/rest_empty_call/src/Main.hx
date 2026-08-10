/**
	Proves that omitting a trailing rest argument supplies an empty Haxe array.

	The same function is also called with two values. This keeps the fixture from
	passing merely because the empty case received an unrelated placeholder.
**/
class Main {
	static function count(...values:Int):Int {
		return values.length;
	}

	static function countExplicit(values:haxe.Rest<Int>):Int {
		return values.length;
	}

	static function main():Void {
		Sys.println('empty=${count()}');
		Sys.println('filled=${count(4, 5)}');
		Sys.println('explicit-empty=${countExplicit()}');
		#if !rest_oracle
		Sys.println('extern-empty=${RestNative.count()}');
		#end
	}
}
