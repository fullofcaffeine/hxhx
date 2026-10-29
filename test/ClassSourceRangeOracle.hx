import haxe.macro.Context;
import haxe.macro.Expr;

/** Observe upstream typed class positions without reading compiler implementation. */
class ClassSourceRangeOracle {
	public static macro function positions():Expr {
		final rows = new Array<Expr>();
		for (type in Context.getModule("SourceClasses"))
			switch (type) {
				case TInst(reference, _):
					final owner = reference.get();
					if (!["Hidden", "HasValue", "Empty", "Foreign", "SourceClasses"].contains(owner.name))
						continue;
					final position = Context.getPosInfos(owner.pos);
					rows.push(macro {name: $v{owner.name}, start: $v{position.min}, end: $v{position.max}});
				case _:
			}
		if (rows.length != 5)
			throw "class source oracle requires all five authored declarations";
		return macro $a{rows};
	}
}
