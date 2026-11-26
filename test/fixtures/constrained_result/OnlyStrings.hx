class OnlyStrings {
	public static function sorted<T:String, A:Array<T>>(arr:A):String
		return "sorted " + arr.length;
}
