import ocaml.StringMap as SMap;
import ocaml.IntMap as IMap;
import ocaml.StringSet as SSet;
import ocaml.IntSet as ISet;

	class Main {
		static function main() {
		var sm:SMap<Int> = SMap.empty();
		sm = SMap.add("a", 1, sm);
		SMap.findOpt("a", sm);
		SMap.mem("a", sm);

		var im:IMap<String> = IMap.empty();
		im = IMap.add(1, "x", im);
		IMap.findOpt(1, im);

		var ss = SSet.empty();
		ss = SSet.add("a", ss);
		SSet.mem("a", ss);

		var iset = ISet.empty();
		iset = ISet.add(1, iset);
		ISet.mem(1, iset);
	}
}
