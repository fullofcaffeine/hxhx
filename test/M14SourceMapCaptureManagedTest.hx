/** Focused map storage proof; the separate full map test retains all broader acceptance cases. */
class M14SourceMapCaptureManagedTest {
	static function main():Void {
		M14SourceMapComprehensionManagedTest.runFixture({
			sourceRoot: "test/oracle/source_comprehension_seed/map_capture",
			module: "MapCapture",
			observer: "test/cpp_managed_heap/MapCaptureObserver.cpp",
			output: ".tmp/source-map-capture-managed",
			marker: "SOURCE_MAP_CAPTURE_NATIVE:PASS"
		});
		Sys.println("SOURCE_MAP_CAPTURE_MANAGED:PASS");
	}
}
