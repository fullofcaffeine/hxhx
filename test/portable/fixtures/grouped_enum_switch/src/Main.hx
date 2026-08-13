enum Kind {
	A;
	B;
	C;
	D;
}

enum Payload {
	Number(value:Int);
	Alternate(value:Int);
	Nothing;
}

class Main {
	static function grouped(kind:Kind):Bool {
		return switch (kind) {
			case A, B: true;
			case C, D: false;
		};
	}

	static function mixed(kind:Kind):String {
		return switch (kind) {
			case A, B: "left";
			case C: "middle";
			case D: "right";
		};
	}

	static function payload(value:Payload):String {
		return switch (value) {
			case Number(number), Alternate(number): 'value:$number';
			case Nothing: "none";
		};
	}

	static function main():Void {
		Sys.println('grouped=${grouped(A)},${grouped(B)},${grouped(C)},${grouped(D)}');
		Sys.println('mixed=${mixed(A)},${mixed(B)},${mixed(C)},${mixed(D)}');
		Sys.println('payload=${payload(Number(5))},${payload(Alternate(6))},${payload(Nothing)}');
	}
}
