/** Observes the declared enum result through ordinary instance calls. */
class EnumReturnProbe {
	static function main():Void {
		switch (new Reader().parse()) {
			case Text(value):
				Sys.println(value);
			case Empty:
				throw "unexpected empty result";
		}
	}
}
