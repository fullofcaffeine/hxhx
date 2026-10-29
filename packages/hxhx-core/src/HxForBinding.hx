/** Authored loop bindings; key/value iteration remains distinct from value iteration. */
enum HxForBinding {
	Value(name:String);
	KeyValue(key:String, value:String);
}

/** Declaration order used by source conversion, typing, and exact local replay. */
function names(binding:HxForBinding):Array<String>
	return switch binding {
		case Value(name): [name];
		case KeyValue(key, value): [key, value];
	};

/** Reconstruct the closed binding form from validated typed declaration names. */
function fromNames(names:Array<String>):HxForBinding
	return switch names {
		case [name]: Value(name);
		case [key, value]: KeyValue(key, value);
		case _: throw "for binding requires one value name or a key/value pair";
	};
