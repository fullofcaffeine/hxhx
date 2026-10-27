/** Imported functions deliberately accept the other enum's argument shape. */
function Build(value:Int, flag:Bool):First
	return First.Build("function", null);

/** An imported alias must obey the same expected-constructor rule. */
function other(value:Int, flag:Bool):First
	return First.Build("alias", null);
