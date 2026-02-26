package haxe.format;

/**
	OCaml target override for `haxe.format.JsonPrinter`.

	Why
	- The upstream implementation relies on dynamic branches where `TFloat` paths can
	  still carry a dynamic value at emission time, which currently generates OCaml
	  type errors in portable builds.
	- We keep the public API and semantics contract, but make the dynamic-to-typed
	  conversions explicit in each branch.

	What
	- Supports JSON encoding for null/bool/int/float/string/object/array.
	- Supports optional `replacer` and pretty-print spacing (`space`) arguments.
	- Preserves upstream-compatible behavior for class/object handling and function fields.

	How
	- Performs branch-local typed casts (`Int`, `Float`, `Bool`, etc.) before writing.
	- Uses a deterministic recursive writer over arrays and objects.
**/
class JsonPrinter {
	public static function print(o:Dynamic, ?replacer:(key:Dynamic, value:Dynamic) -> Dynamic, ?space:String):String {
		final printer = new JsonPrinter(replacer, space);
		printer.writeValue("", o);
		return printer.buffer.toString();
	}

	final buffer:StringBuf;
	final replacer:Dynamic;
	final indentUnit:String;
	final pretty:Bool;
	var depth:Int;

	function new(replacer:Dynamic, space:Null<String>) {
		this.buffer = new StringBuf();
		this.replacer = replacer;
		this.indentUnit = space == null ? "" : space;
		this.pretty = this.indentUnit.length > 0;
		this.depth = 0;
	}

	inline function appendIndent():Void {
		if (!pretty) {
			return;
		}
		buffer.add(StringTools.lpad("", indentUnit, depth * indentUnit.length));
	}

	inline function appendNewline():Void {
		if (pretty) {
			buffer.addChar("\n".code);
		}
	}

	function writeValue(key:Dynamic, value:Dynamic):Void {
		var resolved:Dynamic = value;
		if (replacer != null) {
			resolved = Reflect.callMethod(null, replacer, [key, value]);
		}

		switch (Type.typeof(resolved)) {
			case TUnknown:
				quote("???");
			case TObject:
				writeObject(resolved, Reflect.fields(resolved));
			case TInt:
				final intValue = Std.parseInt(Std.string(resolved));
				buffer.add(Std.string(intValue == null ? 0 : intValue));
			case TFloat:
				final floatValue = Std.parseFloat(Std.string(resolved));
				buffer.add(Math.isFinite(floatValue) ? Std.string(floatValue) : "null");
			case TFunction:
				quote("<fun>");
			case TClass(classType):
				if (classType == String) {
					quote(Std.string(resolved));
				} else if (classType == Array) {
					final arrayValue:Array<Dynamic> = cast resolved;
					writeArray(arrayValue);
				} else if (classType == haxe.ds.StringMap) {
					final mapValue:haxe.ds.StringMap<Dynamic> = cast resolved;
					final objectValue = {};
					for (field in mapValue.keys()) {
						Reflect.setField(objectValue, field, mapValue.get(field));
					}
					writeObject(objectValue, Reflect.fields(objectValue));
				} else if (classType == Date) {
					quote(Std.string(resolved));
				} else {
					final objectFields = Type.getInstanceFields(Type.getClass(resolved));
					writeObject(resolved, objectFields);
				}
			case TEnum(_):
				buffer.add(Std.string(Type.enumIndex(resolved)));
			case TBool:
				buffer.add(resolved == true ? "true" : "false");
			case TNull:
				buffer.add("null");
		}
	}

	function writeArray(values:Array<Dynamic>):Void {
		buffer.addChar("[".code);
		if (values.length == 0) {
			buffer.addChar("]".code);
			return;
		}

		depth += 1;
		for (index in 0...values.length) {
			if (index > 0) {
				buffer.addChar(",".code);
			}
			appendNewline();
			appendIndent();
			writeValue(index, values[index]);
		}
		depth -= 1;
		appendNewline();
		appendIndent();
		buffer.addChar("]".code);
	}

	function writeObject(value:Dynamic, fields:Array<String>):Void {
		buffer.addChar("{".code);
		final printableFields:Array<String> = [];
		for (field in fields) {
			final current = Reflect.field(value, field);
			if (!Reflect.isFunction(current)) {
				printableFields.push(field);
			}
		}

		if (printableFields.length == 0) {
			buffer.addChar("}".code);
			return;
		}

		depth += 1;
		for (index in 0...printableFields.length) {
			final field = printableFields[index];
			if (index > 0) {
				buffer.addChar(",".code);
			}
			appendNewline();
			appendIndent();
			quote(field);
			buffer.addChar(":".code);
			if (pretty) {
				buffer.addChar(" ".code);
			}
			writeValue(field, Reflect.field(value, field));
		}
		depth -= 1;
		appendNewline();
		appendIndent();
		buffer.addChar("}".code);
	}

	function quote(text:String):Void {
		buffer.addChar("\"".code);
		var index = 0;
		while (index < text.length) {
			final code = StringTools.fastCodeAt(text, index);
			index += 1;
			switch (code) {
				case "\"".code:
					buffer.add("\\\"");
				case "\\".code:
					buffer.add("\\\\");
				case "\n".code:
					buffer.add("\\n");
				case "\r".code:
					buffer.add("\\r");
				case "\t".code:
					buffer.add("\\t");
				case 8:
					buffer.add("\\b");
				case 12:
					buffer.add("\\f");
				case value if (value >= 0 && value < 32):
					final hex = StringTools.hex(value, 4);
					buffer.add("\\u" + hex);
				case _:
					buffer.addChar(code);
			}
		}
		buffer.addChar("\"".code);
	}
}
