/**
	Parse error for the Haxe-in-Haxe parser.

	Why:
	- We want deterministic, readable failures in acceptance workloads.
	- Using a dedicated exception type keeps future error reporting (and
	  structured diagnostics) straightforward.

	What:
	- A message and the HxPos where parsing failed.
**/
class HxParseError {
	public final pos:HxPos;
	public final message:String;

	public function new(message:String, pos:HxPos) {
		this.message = message;
		this.pos = pos;
	}

	public function toString():String {
		return message + ' (' + pos.toString() + ')';
	}
}
