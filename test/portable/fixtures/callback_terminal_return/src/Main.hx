/** Result returned across the callback boundary. */
enum Answer {
	Accepted;
	Rejected;
}

/** Proves an explicit callback return does not retain unreachable result locals. */
class Main {
	static function classify(value:String, allowed:Bool):Answer {
		return allowed && value == "yes" ? Accepted : Rejected;
	}

	static function invoke(callback:Int->Answer):Answer {
		return callback(0);
	}

	static function main() {
		final values = ["yes"];
		final answer = invoke(index -> {
			final allowed = index >= 0 && index < values.length;
			final hint = index < 0 || index >= values.length ? "" : values[index];
			return classify(hint, allowed);
		});
		Sys.println(answer == Accepted ? "accepted" : "rejected");
		final read = invoke(index -> {
			final result = classify("yes", index == 0);
			return result;
		});
		Sys.println(read == Accepted ? "read" : "wrong");
		final conditional = invoke(index -> {
			if (index != 0)
				return Rejected;
			return Accepted;
		});
		Sys.println(conditional == Accepted ? "conditional" : "wrong");
	}
}
