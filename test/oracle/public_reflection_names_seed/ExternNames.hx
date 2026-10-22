/** Host metadata determines the reflection result for this built-in constructor. */
@:native("Array") extern class HostArray {}

/** A different host constructor has no Haxe reflection name. */
@:native("Object") extern class HostObject {}

/** Exact host console calls observe values without adding reflection metadata. */
class ExternNames {
	static function main():Void {
		js.Syntax.code("console.log({0})", Type.getClassName(HostArray));
		js.Syntax.code("console.log({0})", Type.getClassName(HostObject));
	}
}
