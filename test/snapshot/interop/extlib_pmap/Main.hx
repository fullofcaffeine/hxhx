import ocaml.extlib.PMap;

class Main {
	static function main() {
		var m:PMap<Int, String> = PMap.empty();
		m = PMap.add(1, "one", m);

		Sys.println(PMap.find(1, m));
		Sys.println(Std.string(PMap.mem(2, m)));
	}
}
