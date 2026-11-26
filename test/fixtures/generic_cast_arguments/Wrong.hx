abstract Words(Array<String>) from Array<String> to Array<String> {}

class Wrong {
	static function same<T>(a:Array<T>, b:Array<T>):Bool
		return a.length == b.length;

	static function main() {
		final words:Words = ["a"];
		same([10], words);
	}
}
