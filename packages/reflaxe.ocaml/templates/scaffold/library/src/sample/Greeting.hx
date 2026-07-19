package sample;

/** Small public Haxe API used by the generated library smoke build. **/
class Greeting {
	public static function message(name:String):String {
		return 'Hello, $name, from {{PROJECT_NAME}}!';
	}
}
