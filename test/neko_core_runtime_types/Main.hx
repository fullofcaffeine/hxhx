class Main {
	static function main():Void {
		var arrayType:Class<Array<Dynamic>> = Array;
		var stringType:Class<String> = String;
		var values = [1, 2];
		Sys.println(values is Array);
		Sys.println("hello" is String);
		Sys.println(null is Array);
		Sys.println(null is String);
		Sys.println(Type.getClass(values) == arrayType);
		Sys.println(Type.getClass("hello") == stringType);
		Sys.println(Type.getClassName(arrayType));
		Sys.println(Type.getClassName(stringType));
	}
}
