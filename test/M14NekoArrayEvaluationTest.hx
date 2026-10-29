/** Compare ordered, nested, throwing and colliding-name Array literals with upstream Neko. */
class M14NekoArrayEvaluationTest {
	static function main():Void
		NekoRuntimeFixture.exercise("test/fixtures/neko_array_evaluation", true);
}
