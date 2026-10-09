import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.Eof;

/** Observe real EOF separately from ordinary failures that happen to use the same message. */
class RuntimeBoundaryCatchMain {
	static function failureKind(input:haxe.io.Input):String {
		try {
			return "line:" + input.readLine();
		} catch (_:Eof) {
			return "eof";
		} catch (message:String) {
			return "string:" + message;
		} catch (error:haxe.Exception) {
			return "exception:" + error.message;
		}
	}

	static function main():Void {
		final lines = new BytesInput(Bytes.ofString("a\nlast"));
		Sys.println("first=" + failureKind(lines));
		Sys.println("partial-line=" + failureKind(lines));
		Sys.println("exhausted=" + failureKind(lines));
		Sys.println("misleading-string=" + failureKind(new NamedFailureInput(false)));
		Sys.println("misleading-exception=" + failureKind(new NamedFailureInput(true)));
		final shortInput = new BytesInput(Bytes.ofString("ab"));
		final buffer = Bytes.alloc(4);
		try {
			shortInput.readFullBytes(buffer, 0, 4);
			Sys.println("partial-read=missing-eof");
		} catch (_:Eof) {
			Sys.println("partial-read=" + buffer.get(0) + "," + buffer.get(1) + "," + buffer.get(2) + "," + buffer.get(3));
		}
		final allInput = new BytesInput(Bytes.ofString("all"));
		Sys.println("read-all=" + allInput.readAll().toString());
		try {
			allInput.readByte();
			Sys.println("read-all-exhausted=false");
		} catch (_:Eof) {
			Sys.println("read-all-exhausted=true");
		}
	}
}

/** These failures deliberately imitate EOF text without throwing the Eof class. */
class NamedFailureInput extends haxe.io.Input {
	final exceptionObject:Bool;

	public function new(exceptionObject:Bool)
		this.exceptionObject = exceptionObject;

	public override function readByte():Int {
		if (exceptionObject)
			throw new haxe.Exception("Eof");
		throw "Eof";
	}
}
