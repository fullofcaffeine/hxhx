package backend.js;

/**
	Render the JavaScript array/object representation boundary for pair iteration.

	Both projected statements and the expression adapter can carry native arrays or
	object-backed maps. Test the saved runtime value once: arrays visit every integer
	index below their current length, including holes and elements appended by the
	body. Objects retain their existing own-key snapshot and string keys. This does
	not implement the Haxe custom keyValueIterator protocol or infer its presence
	from member names; that protocol requires separately selected typed call facts.
 */
function emit(input:{
	writer:JsWriter,
	source:String,
	key:String,
	value:String,
	fresh:String->String,
	body:() -> Void
}):Void {
	final writer = input.writer;
	final array = input.fresh("__array");
	final keys = input.fresh("__keys");
	final index = input.fresh("__i");
	writer.writeln("var " + array + " = Array.isArray(" + input.source + ");");
	writer.writeln("var " + keys + " = " + array + " ? null : Object.keys(" + input.source + ");");
	writer.writeln("for (var "
		+ index
		+ " = 0; "
		+ index
		+ " < ("
		+ array
		+ " ? "
		+ input.source
		+ ".length : "
		+ keys
		+ ".length); "
		+ index
		+ "++) {");
	writer.pushIndent();
	writer.writeln("var " + input.key + " = " + array + " ? " + index + " : " + keys + "[" + index + "];");
	writer.writeln("var " + input.value + " = " + input.source + "[" + input.key + "];");
	input.body();
	writer.popIndent();
	writer.writeln("}");
}
