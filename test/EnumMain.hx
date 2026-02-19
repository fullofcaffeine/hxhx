class EnumMain {
	static function main() {
		var e = MyEnum.C(1, "x");

		switch (e) {
			case A:
				e = B(2);
			case B(i):
				e = C(i, "y");
			case C(i, s):
				e = A;
			default:
		}
	}
}
