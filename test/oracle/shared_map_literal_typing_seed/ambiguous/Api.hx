import haxe.ds.Map;

/** Both explicit overloads accept an empty literal, so neither may be selected by source order. */
extern class Api {
	overload static function pick(value:Array<Int>):Int;
	overload static function pick(value:Map<Int, String>):Bool;
}
