/**
	A string scanner whose cursor is an Int instance field, as in the OCaml
	`Xml` parser state. It needs `cursor.index += n` on a field (not only `++`)
	and `charAt` on a String read from a field, including out-of-range reads.
 */
class Cursor {
	public final source:String;
	public var index:Int;

	public function new(source:String) {
		this.source = source;
		this.index = 0;
	}
}

class Main {
	static function skip(cursor:Cursor, value:String):Bool {
		if (cursor.source.substr(cursor.index, value.length) != value)
			return false;
		cursor.index += value.length;
		return true;
	}

	static function main() {
		final cursor = new Cursor("<a/>");
		Sys.println(skip(cursor, "<"));
		Sys.println(cursor.index);
		Sys.println(cursor.source.charAt(cursor.index));
		cursor.index += 1;
		Sys.println(skip(cursor, "/>"));
		Sys.println(cursor.index);
		cursor.index -= 3;
		cursor.index *= 2;
		Sys.println(cursor.index);
		Sys.println("[" + cursor.source.charAt(cursor.index) + "]");
	}
}
