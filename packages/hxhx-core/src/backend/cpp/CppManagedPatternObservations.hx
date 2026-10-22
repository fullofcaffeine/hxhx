package backend.cpp;

import TypedGuardedPatternPlan;

/**
	Spell pattern observations using exact input types and program-owned enum metadata.
	Columns describe already selected reads, not reconstructed source expressions.
	Nested anonymous fields and Array elements keep their concrete types. Nominal
	object fields require a separate typed member selection and are rejected here.
 */
class CppManagedPatternObservations {
	final columns:Array<GuardedPatternRead>;
	final input:TyType;
	final types:Map<Int, TyType> = new Map();
	final named:HxSwitchPattern->Null<TypedNamedPattern>;
	final casts:Null<CppManagedCastPlan>;
	final enums:Null<CppManagedEnumDescriptors>;

	public function new(input:{
		plan:TypedGuardedPatternPlan,
		type:TyType,
		named:HxSwitchPattern->Null<TypedNamedPattern>,
		?casts:CppManagedCastPlan,
		?enums:CppManagedEnumDescriptors
	}) {
		columns = input.plan.getColumns();
		this.input = input.type;
		named = input.named;
		casts = input.casts;
		enums = input.enums;
	}

	function stored(type:TyType):TyType {
		var result = casts == null ? type : casts.representationType(type);
		while (result.getNullableInner() != null)
			result = result.getNullableInner();
		return result;
	}

	function selection(pattern:HxSwitchPattern):TypedNamedPattern {
		final selected = named(pattern);
		if (selected == null || enums == null)
			throw "managed guarded enum requires its exact named pattern and program descriptor";
		return selected;
	}

	function type(column:Int):TyType {
		if (column < 0 || column >= columns.length)
			throw "managed guarded read references an absent column";
		final previous = types.get(column);
		if (previous != null)
			return previous;
		final selected = switch columns[column] {
			case Input: input;
			case ArrayItem(parent, _): CppManagedArrayRead.elementType(stored(type(parent)), TyType.fromHintText("Int"));
			case ObjectField(parent, name): fieldType(parent, name);
			case EnumArgument(parent, pattern, index):
				final exact = selection(pattern);
				enums.patternPayload(exact, stored(type(parent)), index);
		};
		CppManagedClosureAbi.assertComplete(selected);
		types.set(column, selected);
		return selected;
	}

	function fieldType(parent:Int, name:String):TyType {
		final owner = stored(type(parent));
		final index = owner.getAnonymousFieldNames().indexOf(name);
		if (!owner.isAnonymous() || index < 0)
			throw "managed guarded field requires an exact anonymous field type";
		return owner.getAnonymousFieldTypes()[index];
	}

	/** Tests do not allocate; descriptor equality distinguishes same-named constructors from other enums. */
	public function test(root:String, test:GuardedPatternTest):String {
		final value = root + ".get()";
		return switch test {
			case IsNull: value + ".kind() == hxhx::managed::ValueKind::Null";
			case IsBool(literal): value + ".kind() == hxhx::managed::ValueKind::Boolean && " + value + ".asBoolean() == " + literal;
			case IsInt(literal): value + ".kind() == hxhx::managed::ValueKind::Integer && " + value + ".asInteger() == static_cast<std::int32_t>(" + literal
				+ "LL)";
			case IsString(literal): value
				+ ".kind() == hxhx::managed::ValueKind::String && "
				+ value
				+ ".asString() == "
				+ CppManagedText.literal(literal);
			case ArrayLength(length): layout(value, "ArrayPayload") + " && " + payload(value, "ArrayPayload") + "->size() == " + length;
			case EnumConstructor(pattern, selected):
				final exact = selection(pattern);
				if (selected.getSemanticKey() != exact.getSemanticKey())
					throw "managed guarded pattern differs from its exact constructor selection";
				final target = enums.patternTarget(exact);
				layout(value, "EnumPayload")
				+ " && &"
				+ payload(value, "EnumPayload")
				+ "->descriptor() == &"
				+ target.symbol
				+ " && "
				+ payload(value, "EnumPayload")
				+ "->constructorIndex() == "
				+ target.index;
		};
	}

	/** A physical read returns a copy; the enclosing adapter roots it before the next source effect. */
	public function read(read:GuardedPatternRead, value:Int->String):String {
		return switch read {
			case Input: throw "managed guarded switch cannot read its source twice";
			case ArrayItem(parent, index):
				CppManagedArrayRead.elementType(stored(type(parent)), TyType.fromHintText("Int"));
				payload(value(parent) + ".get()", "ArrayPayload") + "->read(" + index + ")";
			case ObjectField(parent, name):
				fieldType(parent, name);
				final record = payload(value(parent) + ".get()", "RecordPayload");
				final field = CppManagedText.literal(name);
				"("
				+ record
				+ "->contains("
				+ field
				+ ") ? "
				+ record
				+ "->read("
				+ field
				+ ") : hxhx::managed::Value{})";
			case EnumArgument(parent, pattern, index):
				final exact = selection(pattern);
				enums.patternPayload(exact, stored(type(parent)), index);
				payload(value(parent) + ".get()", "EnumPayload") + "->read(" + index + ")";
		};
	}

	static function payload(value:String, name:String):String
		return value + ".asManaged().as<hxhx::managed::" + name + ">()";

	static function layout(value:String, name:String):String
		return value
			+ ".kind() == hxhx::managed::ValueKind::Managed && "
			+ value
			+ ".asManaged().hasLayout<hxhx::managed::"
			+ name
			+ ">()";
}
