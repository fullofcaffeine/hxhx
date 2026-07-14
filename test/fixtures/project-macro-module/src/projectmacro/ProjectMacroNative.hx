package projectmacro;

/** Native handler compiled from Haxe and registered through the project-macro plugin ABI. **/
class ProjectMacroNative {
	public static function nativeExpansion():String {
		return "\"" + ProjectMacroValue.value() + "\"";
	}

	public static function main():Void {}
}
