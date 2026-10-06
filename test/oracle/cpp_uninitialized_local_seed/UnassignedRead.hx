/** Upstream rejects this source; native checked storage must not turn its missing assignment into a value. */
class UnassignedRead {
	static function main():Void {
		var value:Int;
		if (value != 7)
			throw "unassigned read became a value";
	}
}
