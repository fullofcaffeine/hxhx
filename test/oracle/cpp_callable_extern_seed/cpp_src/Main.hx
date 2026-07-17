/** Native C++ output harness for the callable-constraint contract. **/
class Main {
	static function main():Void {
		for (line in CallableExternContract.lines())
			Sys.println(line);
	}
}
