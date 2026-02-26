class Main {
	static function main() {
		final u8 = haxe.io.UInt8Array.fromBytes(haxe.io.Bytes.ofHex("01020304"));
		final u8Sub = u8.sub(1, 2);
		final u8Slice = u8.subarray(1, 3);
		Sys.println("u8=" + (u8 != null) + ":" + (u8Sub != null) + ":" + (u8Slice != null));

		final u32 = haxe.io.UInt32Array.fromBytes(haxe.io.Bytes.ofHex("0102030405060708090A0B0C"));
		final u32Sub = u32.sub(1, 1);
		final u32Slice = u32.subarray(1, 3);
		Sys.println("u32=" + (u32 != null) + ":" + (u32Sub != null) + ":" + (u32Slice != null));
	}
}
