class CycleMain {
	static function main():Void {
		OracleOutput.print("cycle=" + CycleA.value + "/" + CycleB.value);
		OracleOutput.print("events=" + InitLog.events.join(","));
	}
}
