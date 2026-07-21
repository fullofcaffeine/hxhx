class InitLog {
	public static final events:Array<String> = [];

	public static function record(label:String, value:Int):Int {
		events.push(label + "=" + value);
		return value;
	}
}
