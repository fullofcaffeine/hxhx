import haxe.io.Output;

private class StringOutput extends Output {
	final buf:StringBuf;

	public function new() {
		// Intentionally do not call `super()`.
		// Upstream stdlib relies on this being legal for IO subclasses.
		buf = new StringBuf();
	}

	override public function writeByte(c:Int):Void {
		buf.addChar(c);
	}

	public function toString():String {
		return buf.toString();
	}
}

class Main {
	static function main() {
		final out = new StringOutput();
		out.writeString("Hello");
		Sys.println(out.toString());
	}
}
