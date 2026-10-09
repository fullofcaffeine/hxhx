/** Upstream rejects an Int handler after Float because Float already catches Int values. */
class RejectedNumericCatchOrderMain {
	static function main():Void {
		try {
			throw 7;
		} catch (_:Float) {
			Sys.println("float");
		} catch (_:Int) {
			Sys.println("int");
		}
	}
}
