/** Returns a concrete enum through an explicitly nullable function result. */
function optional(enabled:Bool, values:Array<Int>):Null<Choice> {
	if (!enabled)
		return null;
	return concrete(values);
}

function concrete(values:Array<Int>):Choice {
	return Payload(values);
}
