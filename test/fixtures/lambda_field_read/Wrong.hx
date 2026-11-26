class Wrong {
	static function apply<T>(value:T, cb:T->Void):Void
		cb(value);

	static function main() {
		apply({error: 1}, function(res) {
			final text:String = res.error;
		});
	}
}
