class Main {
	static function main():Void {
		var value:Int = 7;
		value;
		{
			var value:Int = 8;
			var nested:Int = value;
		}
		var copied:Int = value;
	}
}
