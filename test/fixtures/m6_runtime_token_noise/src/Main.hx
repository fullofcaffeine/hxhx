class Main {
	static function main() {
		final runtimeLookingTokens = ["HxFile", "HxFileSystem", "HxFileStream", "HxReflect", "HxSys"];
		final joined = runtimeLookingTokens.join(",");
		if (joined.length == 0) {
			throw "unexpected";
		}
	}
}
