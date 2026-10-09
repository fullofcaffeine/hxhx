/** The same loop is not a Dynamic value for an ordinary runtime call. */
class Main {
	static function inspect(value:Dynamic):Void {}

	static function tick(value:Bool):Void {}

	static function main():Void {
		inspect(while (false) {
			tick(false);
		});
	}
}
