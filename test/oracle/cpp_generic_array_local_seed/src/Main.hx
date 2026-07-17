/** Upstream multi-target output harness for the generic Array-local contract. **/
class Main {
	static function emit(value:String):Void {
		#if !js
		Sys.println(value);
		#else
		js.Syntax.code("console.log({0})", value);
		#end
	}

	static function main():Void {
		for (line in GenericArrayLocal.lines())
			emit(line);
	}
}
