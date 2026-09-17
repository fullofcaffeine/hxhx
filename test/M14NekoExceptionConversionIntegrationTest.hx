/** Real exception conversions must load their parameter types without explicit helper roots. */
class M14NekoExceptionConversionIntegrationTest {
	static function main():Void {
		@:privateAccess M14NekoStdIsOfTypeIntegrationTest.assertFixture("test/neko_exception_conversions", "NEKO_EXCEPTION_CONVERSIONS");
	}
}
