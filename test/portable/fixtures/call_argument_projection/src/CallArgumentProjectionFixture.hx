/** Observe omission and rest projection without introducing compiler typing dependencies. */
class CallArgumentProjectionFixture {
	static function main():Void {
		final source = ["left", "right"];
		final selected = TyCallArgumentProjection.project([Supplied(0), Omitted, Supplied(1), Omitted], source, "absent", 2);
		Sys.println(selected.join(","));
		Sys.println(source.join(","));
		Sys.println(TyCallArgumentProjection.project([Omitted, RestElements([0, 1])], [3, 4], -1, 2).join(","));
		Sys.println(TyCallArgumentProjection.project([Omitted, RestElements([]), Omitted], [], "absent", 0).length);
		final spread = [5, 6];
		final projected = TyCallArgumentProjection.project([RestSpread(0)], [spread], new Array<Int>(), 1);
		if (projected.length != 1 || projected[0] != spread)
			throw "rest spread was expanded or copied";
		projected[0].push(7);
		Sys.println(spread.join(","));
		final cell = new Cell(8);
		final placeholder = new Cell(-1);
		final cells = TyCallArgumentProjection.project([Omitted, Supplied(0)], [cell], placeholder, 1);
		if (cells.length != 2 || cells[0] != placeholder || cells[1] != cell)
			throw "projection lost an operand or placeholder identity";
		cells[1].value = 9;
		Sys.println(cell.value);
		var rejected = false;
		try {
			TyCallArgumentProjection.project([Supplied(0)], [1], 0, 2);
		} catch (message:String) {
			if (message != "call argument projection has a stale operand count")
				throw message;
			rejected = true;
		}
		if (!rejected)
			throw "stale operand count was accepted";
		Sys.println("stale-count-rejected");
	}
}

/** A shared object makes accidental operand copying observable. */
class Cell {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}
