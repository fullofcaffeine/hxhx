package reflaxe.ocaml.reports;

import haxe.Json;
import haxe.crypto.Sha256;
import haxe.io.Bytes;

/** A validated report value; host objects cannot reach the byte writer. */
private enum ReportValue {
	Absent;
	Boolean(value:Bool);
	Integer(value:Int);
	Text(value:String);
	Sequence(values:Array<ReportValue>);
	Object(fields:Array<ReportField>);
}

/** One object member, with its UTF-8 name retained for deterministic ordering. */
private typedef ReportField = {
	final name:String;
	final key:Bytes;
	final value:ReportValue;
}

/**
	Encodes report facts with object members ordered by their UTF-8 name bytes.

	Array order is preserved. Scalars use Haxe JSON spelling, with numbers limited
	to Int. This is a report encoding contract, not a general JSON canonicalizer.
	The Dynamic input is the host/JSON boundary: each value is checked and copied
	into a closed recursive type before bytes are written. Classes other than
	String and Array, functions, enums, and non-Int numbers are rejected.
**/
function encode(value:Dynamic):String {
	final buffer = new StringBuf();
	write(snapshot(value, 0), buffer, null);
	return buffer.toString();
}

/** Renders the same ordered report facts with indentation for human inspection. */
function render(value:Dynamic):String {
	final buffer = new StringBuf();
	write(snapshot(value, 0), buffer, "");
	return buffer.toString();
}

/** Hashes the explicit UTF-8 encoding, including non-ASCII report names and values. */
function digest(value:Dynamic):String {
	return "sha256:" + hashUtf8(encode(value));
}

/** Hashes already-encoded report material as UTF-8 bytes, never host string units. */
function hashUtf8(value:String):String {
	return Sha256.make(Bytes.ofString(value)).toHex();
}

/** Validates host tags before the boundary casts; recursion is explicitly bounded. */
private function snapshot(value:Dynamic, depth:Int):ReportValue {
	if (depth > 256)
		throw "Report JSON exceeds the supported nesting depth.";
	return switch (Type.typeof(value)) {
		case TNull: Absent;
		case TBool: Boolean((value : Bool));
		case TInt: Integer((value : Int));
		case TClass(kind):
			if (kind == String) {
				Text((value : String));
			} else if (kind == Array) {
				final values:Array<Dynamic> = value;
				Sequence([for (entry in values) snapshot(entry, depth + 1)]);
			} else {
				throw "Report JSON requires plain objects, arrays, or supported scalars.";
			}
		case TObject:
			final fields:Array<ReportField> = [
				for (name in Reflect.fields(value))
					{
						name: name,
						key: Bytes.ofString(name),
						value: snapshot(Reflect.field(value, name), depth + 1)
					}
			];
			fields.sort((left, right) -> left.key.compare(right.key));
			Object(fields);
		case _: throw "Report JSON contains an unsupported value.";
	};
}

/** Writes validated values directly so host object enumeration cannot reorder them. */
private function write(value:ReportValue, buffer:StringBuf, indent:Null<String>):Void {
	final childIndent = indent == null ? null : indent + "  ";
	switch (value) {
		case Absent:
			buffer.add("null");
		case Boolean(value):
			buffer.add(value ? "true" : "false");
		case Integer(value):
			buffer.add(Json.stringify(value));
		case Text(value):
			buffer.add(Json.stringify(value));
		case Sequence(values):
			buffer.add("[");
			for (index in 0...values.length) {
				if (index != 0)
					buffer.add(",");
				line(buffer, childIndent);
				write(values[index], buffer, childIndent);
			}
			if (values.length != 0)
				line(buffer, indent);
			buffer.add("]");
		case Object(fields):
			buffer.add("{");
			for (index in 0...fields.length) {
				if (index != 0)
					buffer.add(",");
				line(buffer, childIndent);
				final field = fields[index];
				buffer.add(Json.stringify(field.name));
				buffer.add(indent == null ? ":" : ": ");
				write(field.value, buffer, childIndent);
			}
			if (fields.length != 0)
				line(buffer, indent);
			buffer.add("}");
	}
}

private function line(buffer:StringBuf, indent:Null<String>):Void {
	if (indent != null) {
		buffer.add("\n");
		buffer.add(indent);
	}
}
