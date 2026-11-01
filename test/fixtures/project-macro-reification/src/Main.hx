class Main {
	static function join(left:String, right:Int):String
		return left + "-" + right;

	static function main():Void {
		final total = Macros.tally(["alpha", "beta"]);
		Sys.println("total=" + total);
	}
}
