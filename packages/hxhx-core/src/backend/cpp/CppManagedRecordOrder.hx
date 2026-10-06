package backend.cpp;

/**
	Select native record observation order without changing field evaluation order.
	The pinned C++ black-box cases order field identifiers as signed 32-bit values,
	including negative identifiers before positive ones. Native storage receives
	only the resulting names; it does not resolve or infer compiler field facts.
 */
function names(fields:Array<String>):Array<String> {
	final ordered = fields.copy();
	ordered.sort((left, right) -> {
		final a = identifier(left);
		final b = identifier(right);
		return a < b ? -1 : a > b ? 1 : left < right ? -1 : left > right ? 1 : 0;
	});
	return ordered;
}

/** Fixed-width wrapping is part of the selected native field identifier. */
function identifier(name:String):Int {
	var result = 0;
	for (code in new haxe.iterators.StringIteratorUnicode(name))
		result = (result * 223 + code) | 0;
	return result;
}
