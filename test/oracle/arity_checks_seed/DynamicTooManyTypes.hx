/** Dynamic takes at most one type argument; upstream words this case on its own. */
class DynamicTooManyTypes {
	static var field:Dynamic<String, Int>;

	static function main():Void {
		field = null;
	}
}
