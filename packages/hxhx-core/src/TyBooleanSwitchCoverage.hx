/**
	Prove that unguarded patterns cover both values of the primitive Bool type.
	Alternatives and captures preserve literal coverage. Guards contribute no
	proof, and nullable, Dynamic, or nominal inputs require their own domain rules.
 */
function proves(input:TyType, patterns:Array<HxSwitchPattern>):Bool {
	if (input == null || !input.isPrimitive() || input.getDisplay() != "Bool" || patterns == null)
		return false;
	var whenTrue = false;
	var whenFalse = false;
	function collect(pattern:HxSwitchPattern):Void {
		switch pattern {
			case PBool(value):
				if (value)
					whenTrue = true;
				else
					whenFalse = true;
			case POr(alternatives):
				if (alternatives != null)
					for (alternative in alternatives)
						collect(alternative);
			case PCapture(_, inner):
				collect(inner);
			case _:
		}
	}
	for (pattern in patterns)
		collect(pattern);
	return whenTrue && whenFalse;
}
