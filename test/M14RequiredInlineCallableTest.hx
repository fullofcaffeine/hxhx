/** Compare required-inline captured callback behavior with upstream execution. */
class M14RequiredInlineCallableTest {
	static function main():Void {
		final source = sys.io.File.getContent("test/fixtures/required_inline_callable/Main.hx");
		@:privateAccess M14MultiTypeRuntimeTest.run("required_inline_callable", source);
		Sys.println("REQUIRED_INLINE_CALLABLE:PASS");
	}
}
