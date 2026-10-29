/** Independent upstream expectations for the managed counter and signed Int boundaries. */
class Main {
	static function main():Void {
		var calls = 0;
		function count(n:Int):Int {
			calls++;
			return n == 0 ? calls : count(n - 1);
		}
		Sys.println(count(2));
		Sys.println(count(1));
		var upper:Int = 2147483647;
		var lower:Int = -2147483647 - 1;
		Sys.println(upper + 1);
		Sys.println(lower - 1);
		Sys.println(upper++);
		Sys.println(upper);
		Sys.println(lower--);
		Sys.println(lower);
		var effects = 0;
		function effect():Int {
			return ++effects == 1 ? 3 : 8;
		}
		Sys.println(effect() - effect());
		Sys.println(effects);
	}
}
