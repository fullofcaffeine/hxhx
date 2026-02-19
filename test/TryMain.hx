class TryMain {
	static function main() {
		var x = 0;
		try {
			throw "boom";
		} catch (e:Dynamic) {
			x = 1;
		}
	}
}
