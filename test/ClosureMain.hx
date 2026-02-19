class ClosureMain {
	static function main() {
		var x = 0;

		var bump = function() {
			x += 1;
		};

		bump();
		bump();
	}
}
