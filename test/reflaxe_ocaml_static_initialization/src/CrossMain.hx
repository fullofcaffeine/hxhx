class CrossMain {
	static function main():Void {
		OracleOutput.print("cross=" + A.first + "/" + A.fromB + "/" + B.value);
		OracleOutput.print("events=" + InitLog.events.join(","));
	}
}
