/** Expression, block, nested and early-return arrows share one authored function path. */
class ArrowExecution {
	static function main():Void {
		final expression:Int->Int = value -> value + 1;
		final explicit = (value:Int) -> {
			if (value < 0)
				return 3;
			return value + 2;
		};
		final nested:Void->(Int->Int) = () -> item -> item + 4;
		final implicitBlock:Void->Int = () -> {
			7;
		};
		if (expression(1) != 2 || explicit(-1) != 3 || explicit(1) != 3 || nested()(2) != 6 || implicitBlock() != 7)
			throw "arrow result changed";
	}
}
