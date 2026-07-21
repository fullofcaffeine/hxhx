class EarlierHolder {
	public static var value:LaterValue = new LaterValue();
}

class LaterValue {
	public function new() {}
}

class IncompatibleMain {
	static function main():Void {
		OracleOutput.print("unexpected=" + EarlierHolder.value);
	}
}
