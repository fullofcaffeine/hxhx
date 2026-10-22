/** Check replacement and captured values through ordinary upstream map operations. */
class MapCaptureOracle {
	static function main():Void {
		final map = MapCapture.collect();
		if (map.get(0)() != 2 || map.get(1)() != 3)
			throw "map replacement lost its iteration binding";
		final strings = MapCapture.strings();
		if (strings.get("b")() != 2 || strings.get("a")() != 3)
			throw "string map replacement lost its iteration binding";
		Sys.println("SOURCE_MAP_CAPTURE_NATIVE:PASS");
	}
}
