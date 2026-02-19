class Main {
	static function main() {
		Sys.println("x0=" + C.x);
		C.x = 2;
		C.x += 3;
		C.x++;
		Sys.println("x1=" + C.x);
	}
}
