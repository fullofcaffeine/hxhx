class Main {
	static function main() {
		final max = 0x7fffffff;
		Sys.println("int=" + max);
		Sys.println("add1=" + (max + 1));
		Sys.println("add2=" + (max + 2));

		final mul = 0x40000000 * 2;
		Sys.println("mul=" + mul);

		Sys.println("shl=" + (1 << 31));
		Sys.println("shr=" + (-1 >> 1));
		Sys.println("ushr=" + (-1 >>> 1));

		Sys.println("and=" + (0xf0f0f0f0 & 0x0f0f0f0f));
		Sys.println("or=" + (0xf0000000 | 0x0f));
		Sys.println("xor=" + (0x12345678 ^ 0xffffffff));
		Sys.println("not=" + (~0));

		Sys.println("OK int32_semantics");
	}
}

