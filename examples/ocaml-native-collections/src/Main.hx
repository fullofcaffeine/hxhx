import ocaml.Array as OArray;
import ocaml.Bytes as OBytes;
import ocaml.Char as OChar;
import ocaml.Hashtbl as OHashtbl;
import ocaml.Seq as OSeq;

class Main {
	static function main() {
		final a = OArray.make(3, 0);
		OArray.set(a, 0, 7);
		Sys.println("array0=" + OArray.get(a, 0));
		Sys.println("arrayLen=" + OArray.length(a));

		final h = OHashtbl.create(8);
		OHashtbl.add(h, "a", 1);
		OHashtbl.add(h, "b", 2);
		Sys.println("hashtblLen=" + OHashtbl.length(h));
		Sys.println("hashtblA=" + OHashtbl.find(h, "a"));

		final b = OBytes.make(2, OChar.ofInt(65));
		Sys.println("bytes=" + OBytes.toString(b));

		final seq = OSeq.append(OSeq.return_(1), OSeq.return_(2));
		final sum = OSeq.foldLeft((acc, x) -> acc + x, 0, seq);
		Sys.println("seqSum=" + sum);
	}
}

