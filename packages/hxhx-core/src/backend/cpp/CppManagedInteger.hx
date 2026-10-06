package backend.cpp;

/** Int and nullable Int operations retain distinct comparison and arithmetic null behavior. */
function resultType(op:String, left:TyType, right:TyType):TyType {
	if (!integerType(left) || !integerType(right))
		throw "managed integer operation requires exact Int or nullable Int operands: "
			+ op
			+ " ("
			+ left.getSemanticKey()
			+ ", "
			+ right.getSemanticKey()
			+ ")";
	return switch op {
		case "+" | "-" | "*": TyType.fromHintText("Int");
		case "==" | "!=" | "<" | "<=" | ">" | ">=": TyType.fromHintText("Bool");
		case _: throw "managed integer operator requires explicit lowering";
	};
}

/** Admit one nullable wrapper only; erased or unrelated scalar types cannot select integer semantics. */
function integerType(type:TyType):Bool
	return type.getSemanticKey() == "primitive:Int" || type.getSemanticKey() == "nullable:primitive:Int";

/** Native C++ converts absent nullable integers to zero only for numeric use, never for comparison identity. */
function numericValue(type:TyType, value:String):String {
	if (!integerType(type))
		throw "managed integer read requires exact Int or nullable Int";
	final read = CppManagedLeaf.read(TyType.fromHintText("Int"), value);
	return type.isNullable() ? "(" + value + ".kind() == hxhx::managed::ValueKind::Null ? 0 : " + read + ")" : read;
}

/**
	Compute from already sequenced Int operands. Every product of two signed
	32-bit values fits in Int64. Reduce the wide result modulo 2^32 through an
	unsigned conversion, then map it into the signed range before the final cast.
	This avoids signed-overflow UB and out-of-range unsigned-to-signed casts.
	Float operations and coercions remain separate contracts.
 */
function compute(op:String, leftType:TyType, rightType:TyType, left:String, right:String, destination:String, prefix:String, indent:String):Array<String> {
	final type = resultType(op, leftType, rightType);
	final a = numericValue(leftType, left);
	final b = numericValue(rightType, right);
	if (type.getSemanticKey() == "primitive:Bool") {
		var comparison = a + " " + op + " " + b;
		if (leftType.isNullable() || rightType.isNullable()) {
			final absentLeft = "(" + left + ".kind() == hxhx::managed::ValueKind::Null)";
			final absentRight = "(" + right + ".kind() == hxhx::managed::ValueKind::Null)";
			final absentResult = switch op {
				case "!=": absentLeft + " != " + absentRight;
				case "==" | "<=" | ">=": absentLeft + " && " + absentRight;
				case _: "false";
			};
			comparison = "(" + absentLeft + " || " + absentRight + ") ? (" + absentResult + ") : (" + comparison + ")";
		}
		return [
			indent + destination + ".set(hxhx::managed::Value::boolean(" + comparison + "));"
		];
	}
	final wide = prefix + "wide";
	final bits = prefix + "bits";
	return [indent
		+ "const std::int64_t "
		+ wide
		+ " = static_cast<std::int64_t>("
		+ a
		+ ") "
		+ op
		+ " static_cast<std::int64_t>("
		+ b
		+ ");",
		indent
		+ "const std::uint32_t "
		+ bits
		+ " = static_cast<std::uint32_t>("
		+ wide
		+ ");",
		indent
		+ destination
		+ ".set(hxhx::managed::Value::integer(static_cast<std::int32_t>("
		+ bits
		+ " > 2147483647LL ? "
		+ "static_cast<std::int64_t>("
		+ bits
		+ ") - 4294967296LL : static_cast<std::int64_t>("
		+ bits
		+ ")"
		+ ")));"];
}
