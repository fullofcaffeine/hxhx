class Main {
	static function main() {
		final key = haxe.io.Bytes.ofString("key");
		final msg = haxe.io.Bytes.ofString("abc");

		final md5 = new haxe.crypto.Hmac(haxe.crypto.Hmac.HashMethod.MD5).make(key, msg).toHex();
		final sha1 = new haxe.crypto.Hmac(haxe.crypto.Hmac.HashMethod.SHA1).make(key, msg).toHex();
		final sha256 = new haxe.crypto.Hmac(haxe.crypto.Hmac.HashMethod.SHA256).make(key, msg).toHex();

		Sys.println("hmac-md5=" + md5);
		Sys.println("hmac-sha1=" + sha1);
		Sys.println("hmac-sha256=" + sha256);
	}
}
