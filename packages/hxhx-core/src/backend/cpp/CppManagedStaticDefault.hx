package backend.cpp;

/**
	Choose the native zero/null storage default from exact typed representation facts.
	Static startup and missing Array elements share these C++ defaults.
	Abstracts retain source identity but use their substituted backing type for
	storage. This does not authorize implicit conversions, abstract operators, or
	Float behavior. Nullable types preserve null even when their inner type is scalar.
	The enclosing storage plan checks program revisions once before visiting fields.
 */
function render(program:CppTypedProgramProjection, source:TyType):String {
	final visiting = new haxe.ds.StringMap<Bool>();
	function select(type:TyType):String {
		CppManagedClosureAbi.assertComplete(type);
		if (CppManagedClassValueType.selects(program, type))
			return "hxhx::managed::Value{}";
		return switch type.getSemanticKey() {
			case "primitive:Int": "hxhx::managed::Value::integer(0)";
			case "primitive:Bool": "hxhx::managed::Value::boolean(false)";
			case "primitive:String": "hxhx::managed::Value{}";
			case _:
				if (type.isDynamic() || type.isNullable() || type.isAnonymous() || type.isFunction()) {
					"hxhx::managed::Value{}";
				} else if (type.getNominalIdentity() != null) {
					final identity = type.getNominalIdentity().getCanonicalName();
					final facts = program.requireClass(program.requireClassIdentity(identity)).requireSemanticFacts();
					switch facts.getNominalKind() {
						case ClassInstance | EnumValue: "hxhx::managed::Value{}";
						case AbstractValue(underlying):
							if (visiting.exists(identity))
								throw "managed static default contains a cyclic abstract representation: " + identity;
							visiting.set(identity, true);
							final bindings = TyTypeSubstitution.bind(facts.getTypeParameterIds(), type.getTypeArguments(), identity);
							final result = select(TyTypeSubstitution.apply(underlying, bindings));
							visiting.remove(identity);
							result;
					}
				} else {
					throw "managed static default requires an explicit type contract: " + type.getSemanticKey();
				}
		};
	}
	return select(source);
}
