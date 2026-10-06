package backend.cpp;

/** Construct one typed aggregate with ordered rooted children and atomic result publication. */
typedef CppManagedAggregateInput = {
	final occurrence:TypedBackendAggregateOccurrence;
	final ?classes:CppManagedClassStorage;
	final ?enums:CppManagedEnumDescriptors;
	final ?casts:CppManagedCastPlan;
	final ?applicationType:TyType->TyType;
	final heap:String;
	final destination:String;
	final renderValue:(HxExpr, String, String) -> Array<String>;
}

/**
	Allocate trace-safe storage before child effects, then initialize in source order.
	The parent and current child remain rooted throughout collecting callbacks.
	Previously initialized children live through the parent's traced edges. Only a
	fully initialized aggregate replaces the caller's result; exceptions unwind
	all temporary roots. Numeric and structural conversions need separate plans.
 */
function render(input:CppManagedAggregateInput, indent:String):Array<String> {
	final occurrence = input.occurrence;
	final type = input.applicationType == null ? occurrence.getType() : input.applicationType(occurrence.getType());
	new CppManagedClosureAbi(TyType.functionType([], type));
	final names = switch occurrence.getExpression() {
		case EAnon(names, _): names.copy();
		case EArrayDecl(_): null;
		case _: throw "managed aggregate requires its projected construction";
	};
	final children = occurrence.getChildren();
	final types = [
		for (type in occurrence.getChildTypes())
			input.applicationType == null ? type : input.applicationType(type)
	];
	final identity = type.getNominalIdentity();
	if (names == null && identity != null && identity.getCanonicalName() == "haxe.ds.Map")
		return CppManagedMapLiteral.render(input, indent);

	final expected = new Array<TyType>();
	if (names == null) {
		final identity = type.getNominalIdentity();
		if (identity == null || identity.getCanonicalName() != "Array" || type.getTypeArguments().length != 1)
			throw "managed array construction requires the resolved Array provider";
		for (_ in children)
			expected.push(type.getTypeArguments()[0]);
	} else {
		if (!type.isAnonymous() || type.getAnonymousFieldNames().length != names.length)
			throw "managed record construction requires exact structural fields";
		final seen = new Map<String, Bool>();
		for (name in names) {
			final index = type.getAnonymousFieldNames().indexOf(name);
			if (index < 0 || seen.exists(name))
				throw "managed record construction requires distinct typed fields";
			seen.set(name, true);
			expected.push(type.getAnonymousFieldTypes()[index]);
		}
	}
	for (index in 0...children.length)
		if (!CppManagedValueTransfer.accepts(expected[index], types[index], input.casts)
			&& !CppManagedNumericErasure.selects(expected[index], types[index], input.casts))
			throw "managed aggregate child requires an explicit typed conversion";
	final parent = input.destination + "_aggregate";
	final child = input.destination + "_element";
	final payload = names == null ? "ArrayPayload" : "RecordPayload";
	final representation = names == null ? ", " + CppManagedArrayRepresentation.select(type.getTypeArguments()[0], input.casts) : "";
	final lines = [indent + "{",
		indent
		+ "  hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::"
		+ payload
		+ ">> "
		+ parent
		+ "("
		+ input.heap
		+ ");",
		indent + "  " + input.heap + ".allocateInto(" + parent + representation + ");"
	];
	if (children.length > 0)
		lines.push(indent + "  hxhx::managed::Root<hxhx::managed::Value> " + child + "(" + input.heap + ");");
	for (index in 0...children.length) {
		for (line in input.renderValue(children[index], child, indent + "  "))
			lines.push(line);
		for (line in CppManagedValueTransfer.convertRoot(expected[index], types[index], child, indent + "  ", input.casts))
			lines.push(line);
		lines.push(indent
			+ "  "
			+ parent
			+ ".get()->"
			+ (names == null ? "append(" : "define(" + CppManagedText.literal(names[index]) + ", ")
			+ child
			+ ".get());");
		lines.push(indent + "  " + child + ".set({});");
	}
	lines.push(indent + "  " + input.destination + ".set(hxhx::managed::Value::managed(" + parent + ".get()));");
	lines.push(indent + "}");
	return lines;
}
