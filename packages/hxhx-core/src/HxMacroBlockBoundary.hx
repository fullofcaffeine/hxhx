/**
	A name-free evaluation sequence does not retain the source's brace groups.
	Macro adapters must reject it until structural source blocks survive typing;
	inventing an EBlock here would merge or add groups that a macro can observe.
**/
final missingSourceGroup = "macro block parsing is unsupported: source brace grouping was lost before macro conversion; structural source blocks are required";
