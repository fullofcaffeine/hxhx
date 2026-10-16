#pragma once

#include "ManagedValue.hpp"
#include <cstdlib>

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

// The generated program selects any authored conversion methods before linking.
// This callback transports a rooted String result, including null and exceptions.
using EqualityStringConversion = void (*)(Heap&, Value, Root<Value>&);

inline bool enumPayloadEquality(Heap&, const Value&, const Value&, EqualityStringConversion);

// Immutable enum edges remain rooted while a String payload invokes user code.
// Allocation identity is deliberately insufficient: a NaN payload makes even
// the same enum allocation unequal to itself on the observed native target.
inline bool enumEquality(Heap& heap, Value left, Value right, EqualityStringConversion convert) {
  Root<Value> a(heap, left), b(heap, right), first(heap), second(heap);
  const auto x = a.get().asManaged().as<EnumPayload>();
  const auto y = b.get().asManaged().as<EnumPayload>();
  if (&x->descriptor() != &y->descriptor() || x->constructorIndex() != y->constructorIndex()) return false;
  for (std::size_t index = 0; index < x->size(); ++index) {
    first.set(x->read(index));
    second.set(y->read(index));
    if (!enumPayloadEquality(heap, first.get(), second.get(), convert)) return false;
  }
  return true;
}

// These conversions belong only to native enum payload comparison. They are
// not Std.parseFloat, casts, or ordinary Dynamic equality. The independent
// oracle preserves prefix parsing, invalid-text zero, and asymmetric conversion.
inline bool enumPayloadEquality(Heap& heap, const Value& left, const Value& right, EqualityStringConversion convert) {
  if (left.kind() == ValueKind::Null) return right.kind() == ValueKind::Null;
  if (right.kind() == ValueKind::Null)
    throw std::invalid_argument("unsupported upstream enum comparison with non-null left and null right payload (haxe_ocaml-rirak)");
  if (equalityNumeric(left.kind())) {
    double number = 0.0;
    if (equalityNumeric(right.kind())) number = equalityNumber(right);
    else if (right.kind() == ValueKind::String) number = std::strtod(right.asString().c_str(), nullptr);
    return equalityNumber(left) == number;
  }
  if (left.kind() == ValueKind::String) {
    if (right.kind() == ValueKind::String) return left.asString() == right.asString();
    if (convert == nullptr)
      throw std::invalid_argument("managed enum comparison requires planned string conversion");
    Root<Value> result(heap);
    convert(heap, right, result);
    if (result.get().kind() == ValueKind::Null) return false;
    if (result.get().kind() != ValueKind::String)
      throw std::invalid_argument("enum comparison conversion returned a non-String value");
    return left.asString() == result.get().asString();
  }
  if (left.kind() != right.kind()) return false;
  if (left.kind() == ValueKind::Descriptor) return left.asDescriptor() == right.asDescriptor();
  if (left.kind() == ValueKind::EnumDescriptor) return left.asEnumDescriptor() == right.asEnumDescriptor();
  const auto a = left.asManaged(), b = right.asManaged();
  if (a.hasLayout<EnumPayload>() && b.hasLayout<EnumPayload>())
    return enumEquality(heap, left, right, convert);
  return a == b;
}

// Operands remain rooted by the generated caller throughout evaluation. Enums
// can invoke the selected String conversion and propagate its effects. Inequality is
// a separate operation: hxcpp returns false for BOTH operators between a
// non-null String and a number/Bool. Enum payload comparison has its own rule.
inline bool dynamicEquality(Heap& heap, const Value& left, const Value& right, bool unequal, EqualityStringConversion convert) {
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
    case ValueKind::EnumDescriptor:
      equal = left.asEnumDescriptor() == right.asEnumDescriptor();
      break;
    case ValueKind::Managed: {
      const auto first = left.asManaged();
      const auto second = right.asManaged();
      if (first.hasLayout<EnumPayload>() && second.hasLayout<EnumPayload>())
        equal = enumEquality(heap, left, right, convert);
      else equal = first == second;
      break;
    }
    default: throw std::logic_error("managed equality has an unhandled value kind");
  }
  return unequal ? !equal : equal;
}

}
