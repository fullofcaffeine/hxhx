/**
	Checks an indexed assignment inside two nested functions.

	The receiver, index, and right-hand side each record one event. This makes the
	test sensitive to both the final value and reflaxe.ocaml's accepted
	left-to-right, exactly-once contract for `receiver()[index()] = rhs()`. The
	separate stock-Haxe oracle records target-specific disagreements instead of
	hiding them behind one expected output.
**/
class Main {
	static final events:Array<String> = [];
	static final values:Array<Int> = [10, 20];
	static var receiverCalls = 0;
	static var indexCalls = 0;
	static var rightHandSideCalls = 0;

	static function emit(line:String):Void {
		#if js
		js.Syntax.code("console.log({0})", line);
		#else
		Sys.println(line);
		#end
	}

	static function receiver():Array<Int> {
		receiverCalls++;
		events.push("array");
		return values;
	}

	static function index():Int {
		indexCalls++;
		events.push("index");
		return 1;
	}

	static function rhs():Int {
		rightHandSideCalls++;
		events.push("rhs");
		return 7;
	}

	static function exercise():Int {
		function outer():Int {
			function inner():Int {
				return receiver()[index()] = rhs();
			}

			return inner();
		}

		return outer();
	}

	static function main():Void {
		final result = exercise();
		emit("result=" + result + " final=" + values[1] + " calls=" + receiverCalls + "," + indexCalls + "," + rightHandSideCalls + " events="
			+ events.join(","));
	}
}
