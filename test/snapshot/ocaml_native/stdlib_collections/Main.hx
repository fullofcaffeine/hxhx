import ocaml.Array as OArray;
import ocaml.Bytes as OBytes;
import ocaml.Char as OChar;
import ocaml.Hashtbl as OHashtbl;
import ocaml.Seq as OSeq;

class Main {
	static function main() {
		final a = OArray.make(3, 1);
		OArray.set(a, 0, 42);
		final b = OArray.map(x -> x + 1, a);
		OArray.iter(x -> {
			final _ = x;
		}, b);

		final h = OHashtbl.create(16);
		OHashtbl.add(h, "k", 123);
		OHashtbl.replace(h, "k", 124);
		OHashtbl.remove(h, "missing");
		OHashtbl.findOpt(h, "missing");
		OHashtbl.find(h, "k");

		// Optional labelled argument interop:
		// OCaml: `Hashtbl.create ?random:<bool option> <size>`
		OHashtbl.create(16, true);

		final bytes = OBytes.ofString("hi");
		final bytes2 = OBytes.make(3, OChar.ofInt(97));
		OBytes.sub(bytes2, 0, OBytes.length(bytes));
		OBytes.toString(bytes);

		final s = OSeq.append(OSeq.return_(1), OSeq.return_(2));
		OSeq.iter(x -> {
			final _ = x;
		}, OSeq.map(x -> x + 1, s));

		// Ensure OCaml-native abstract types can appear in emitted type annotations.
		new Box(a, h);
	}
}
