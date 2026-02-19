package backend.js;

/**
	Small indentation-aware JS text writer for Stage3 backend bring-up.

	Why
	- The MVP JS backend needs deterministic, readable output with minimal allocation churn.
	- Keeping writer concerns separate from emission logic keeps the emitter code focused.
**/
class JsWriter {
	final out:StringBuf = new StringBuf();
	var indent:Int = 0;
	final unit:String;

	public function new(?indentUnit:String) {
		this.unit = indentUnit == null ? "  " : indentUnit;
	}

	public function pushIndent():Void {
		indent += 1;
	}

	public function popIndent():Void {
		if (indent > 0)
			indent -= 1;
	}

	public function writeln(line:String):Void {
		for (_ in 0...indent)
			out.add(unit);
		out.add(line == null ? "" : line);
		out.add("\n");
	}

	public function toString():String {
		return out.toString();
	}
}
