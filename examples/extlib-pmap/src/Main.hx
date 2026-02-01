import ocaml.extlib.PMap;

class Main {
	static function main() {
		var m:PMap<Int, String> = PMap.empty();
		m = PMap.add(1, "one", m);
		m = PMap.add(2, "two", m);

		Sys.println(PMap.find(2, m));
		Sys.println(Std.string(PMap.mem(3, m)));
	}
}
