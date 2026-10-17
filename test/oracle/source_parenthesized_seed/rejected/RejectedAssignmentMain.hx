/** Upstream parses this grouping but rejects it as an assignment destination. */
class RejectedAssignmentMain {
	static function main():Void {
		var value = 1;
		((value)) = 4;
		Sys.println(value);
	}
}
