/** Compare array producer results after erasure with independent upstream output. */
class M14Stage3ArrayProducerStringTest {
	static function main():Void {
		M14Stage3BoolStringTest.run("ArrayProducerMain", "array-producer.expected.stdout");
		Sys.println("M14_STAGE3_ARRAY_PRODUCER_STRING:PASS");
	}
}
