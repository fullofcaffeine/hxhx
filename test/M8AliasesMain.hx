import haxe.io.BytesBuffer;

class M8AliasesMain {
	static function main() {
		// Pull in a nested stdlib module to ensure alias modules are emitted.
		final bb = new BytesBuffer();
		bb.addByte(65);
		Sys.println(bb.getBytes().get(0));
	}
}
