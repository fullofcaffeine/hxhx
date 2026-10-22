#pragma once

#include "ManagedValue.hpp"

namespace hxhx::managed {

// Immutable physical words selected by the Haxe provider. This payload has no
// ordinary class descriptor; a nominal cast must never authorize its fields.
struct Int64Payload {
  const std::int32_t high;
  const std::int32_t low;
  Int64Payload(std::int32_t upper, std::int32_t lower) noexcept : high(upper), low(lower) {}
};

template<> struct Trace<Int64Payload> {
  static void visit(const Int64Payload&, Visitor&) noexcept {}
};

inline bool isInt64Payload(const Value& value) noexcept {
  return value.kind() == ValueKind::Managed && value.asManaged().hasLayout<Int64Payload>();
}

inline Value boxInt64(Heap& heap, std::int32_t high, std::int32_t low) {
  Root<Ref<Int64Payload>> storage(heap);
  heap.allocateInto(storage, high, low);
  return Value::managed(storage.get());
}

// Only the selected Int64 provider asks this storage question. It does not
// broaden Std.isOfType, private class membership, or unchecked downcasts.
inline bool isInt64Value(const Value& value) noexcept {
  return value.kind() == ValueKind::Integer || isInt64Payload(value);
}

inline std::int32_t int64High(const Value& value) {
  if (value.kind() == ValueKind::Integer) return value.asInteger() < 0 ? -1 : 0;
  if (isInt64Payload(value)) return value.asManaged().as<Int64Payload>()->high;
  throw std::invalid_argument("unsupported Dynamic-to-Int64 coercion; expected integer storage");
}

inline std::int32_t int64Low(const Value& value) {
  if (value.kind() == ValueKind::Integer) return value.asInteger();
  if (isInt64Payload(value)) return value.asManaged().as<Int64Payload>()->low;
  throw std::invalid_argument("unsupported Dynamic-to-Int64 coercion; expected integer storage");
}

// Wide signed arithmetic stays in range even at INT64_MIN/MAX. Converting the
// low word to unsigned retains its bits without an implementation-defined cast.
inline std::string int64String(const Value& value) {
  const auto high = static_cast<std::int64_t>(int64High(value));
  const auto low = static_cast<std::uint32_t>(int64Low(value));
  return std::to_string(high * INT64_C(4294967296) + low);
}

}
