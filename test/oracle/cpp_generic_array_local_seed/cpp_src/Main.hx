/** Native C++ output harness for the shared generic Array-local contract. **/
class Main {
	static function emit(value:String):Void {
		Sys.println(value);
	}

	static function main():Void {
		for (line in GenericArrayLocal.lines())
			emit(line);
	}
}
