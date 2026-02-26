class HttpNullableBytesMain {
	static function main() {
		final http = new haxe.Http("http://example.invalid/path");
		final responseData = http.responseData;
		if (responseData == null) {
			Sys.println("response=null");
		} else {
			Sys.println("response.len=" + responseData.length);
		}
	}
}
