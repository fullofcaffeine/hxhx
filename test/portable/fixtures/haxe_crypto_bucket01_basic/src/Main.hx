class Main {
	static function main() {
		final bytes = haxe.io.Bytes.ofString("abc");
		Sys.println("adler=" + haxe.crypto.Adler32.make(bytes));
		Sys.println("crc=" + haxe.crypto.Crc32.make(bytes));
		Sys.println("base64=" + haxe.crypto.Base64.encode(bytes));
		Sys.println("base64url=" + haxe.crypto.Base64.urlEncode(bytes));

		final baseCode = new haxe.crypto.BaseCode(haxe.crypto.Base64.BYTES);
		Sys.println("basecode=" + baseCode.encodeString("abc"));

		Sys.println("md5=" + haxe.crypto.Md5.encode("abc"));
		Sys.println("sha1=" + haxe.crypto.Sha1.encode("abc"));
		Sys.println("sha224=" + haxe.crypto.Sha224.encode("abc"));
		Sys.println("sha256=" + haxe.crypto.Sha256.encode("abc"));
	}
}
