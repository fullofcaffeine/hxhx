/** Observe upstream operand failures separately from the managed target's native observer. */
class FailureOracle {
	static function main():Void {
		final mode = switch Sys.args()[0] {
			case "success": 0;
			case "receiver": 1;
			case "argument": 2;
			case "null": 3;
			case _: throw "unknown interface observation";
		};
		var result = -1;
		var outcome = "returned";
		try {
			result = Main.callEdge(mode);
		} catch (failure:haxe.Exception) {
			outcome = failure.message;
		}
		Sys.println(outcome);
		Sys.println(result);
		Sys.println(Main.effects);
	}
}
