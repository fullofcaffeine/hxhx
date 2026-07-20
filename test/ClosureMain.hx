class ClosureMain {
	static function main() {
		var x = 0;

		var bump = function() {
			var increment = 0;
			increment = 1;
			x += increment;
		};

		bump();
		bump();
	}
}
