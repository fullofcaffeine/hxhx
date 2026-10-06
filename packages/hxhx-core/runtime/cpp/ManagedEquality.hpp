#pragma once

#include "ManagedValue.hpp"

namespace hxhx::managed {

// Only the Haxe emitter's erased equality operation calls this module. These
// predicates do not select source overloads or authorize numeric conversions.
inline bool equalityNumeric(ValueKind kind) noexcept {
  return kind == ValueKind::Boolean || kind == ValueKind::Integer || kind == ValueKind::Float;
}

// Every Int32 is exactly representable as double. Check the tag before reading;
// an unsupported value must not acquire a fabricated numeric zero.
inline double equalityNumber(const Value& value) {
  switch (value.kind()) {
    case ValueKind::Boolean: return value.asBoolean() ? 1.0 : 0.0;
    case ValueKind::Integer: return value.asInteger();
    case ValueKind::Float: return value.asFloat();
    default: throw std::invalid_argument("managed equality requires a numeric operand");
  }
}

// Operands remain rooted by the generated caller throughout evaluation. This
// operation does not allocate managed values or invoke user code. Inequality is
// a separate operation: hxcpp returns false for BOTH operators between a
// non-null String and a number/Bool. Enum payload comparison has a different,
// asymmetric conversion contract; rejecting it here prevents plausible wrong
// identity results while its complete implementation remains tracked in rirak.
inline bool dynamicEquality(const Value& left, const Value& right, bool unequal) {
  const auto a = left.kind();
  const auto b = right.kind();
  if (a == ValueKind::Null || b == ValueKind::Null)
    return unequal ? a != b : a == b;
  const bool numericA = equalityNumeric(a);
  const bool numericB = equalityNumeric(b);
  if (numericA && numericB)
    return unequal ? equalityNumber(left) != equalityNumber(right) : equalityNumber(left) == equalityNumber(right);
  if ((numericA && b == ValueKind::String) || (a == ValueKind::String && numericB))
    return false;
  if (a != b) return unequal;
  bool equal;
  switch (a) {
    case ValueKind::String:
      equal = left.asString() == right.asString();
      break;
    case ValueKind::Descriptor:
      equal = left.asDescriptor() == right.asDescriptor();
      break;
    case ValueKind::Managed: {
      const auto first = left.asManaged();
      const auto second = right.asManaged();
      if (first.hasLayout<EnumPayload>() && second.hasLayout<EnumPayload>())
        throw std::invalid_argument("unsupported managed Dynamic enum equality (haxe_ocaml-rirak)");
      equal = first == second;
      break;
    }
    default: throw std::logic_error("managed equality has an unhandled value kind");
  }
  return unequal ? !equal : equal;
}

}
