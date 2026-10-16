#pragma once

#include "ManagedThrow.hpp"
#include <array>
#include <string_view>

namespace hxhx::managed {

// Haxe selects the exact descriptors and public names. These entries only
// associate existing static identities with names; they never own instances.
struct ClassReflectionEntry { const ClassDescriptor* descriptor; std::string_view name; };
struct EnumReflectionEntry { const EnumDescriptor* descriptor; std::string_view name; };

inline Value reflectionClass(const Value& value, const ClassDescriptor* stringType, const ClassDescriptor* arrayType) {
  if (value.kind() == ValueKind::String) return Value::descriptor(stringType);
  if (value.kind() != ValueKind::Managed) return {};
  const auto ref = value.asManaged();
  if (ref.hasLayout<ArrayPayload>()) return Value::descriptor(arrayType);
  if (ref.hasLayout<InstancePayload>()) return Value::descriptor(&ref.as<InstancePayload>()->descriptor());
  return {};
}

inline Value reflectionEnum(const Value& value) {
  if (value.kind() != ValueKind::Managed || !value.asManaged().hasLayout<EnumPayload>()) return {};
  return Value::enumDescriptor(&value.asManaged().as<EnumPayload>()->descriptor());
}

// Check table membership before reading a descriptor. A handle from another
// generated program cannot borrow a same-named local identity.
inline Value reflectionClassName(const Value& value, const ClassReflectionEntry* entries, std::size_t count) {
  if (value.kind() == ValueKind::Null) return {};
  const auto descriptor = value.asDescriptor();
  for (std::size_t index = 0; index < count; ++index)
    if (entries[index].descriptor == descriptor) return Value::string(std::string(entries[index].name));
  throw std::invalid_argument("class reflection requires a program-owned descriptor");
}

inline Value reflectionEnumName(const Value& value, const EnumReflectionEntry* entries, std::size_t count) {
  if (value.kind() == ValueKind::Null) return {};
  const auto descriptor = value.asEnumDescriptor();
  for (std::size_t index = 0; index < count; ++index)
    if (entries[index].descriptor == descriptor) return Value::string(std::string(entries[index].name));
  throw std::invalid_argument("enum reflection requires a program-owned descriptor");
}

// Unknown names return null. Haxe leaves null input unspecified; this selected
// native policy matches eval by throwing through ordinary rooted transport.
inline Value reflectionResolveClass(Heap& heap, const Value& value, const ClassReflectionEntry* entries, std::size_t count) {
  if (value.kind() == ValueKind::Null) throw ThrownValue(heap, Value::string("Null Access"));
  const auto& name = value.asString();
  for (std::size_t index = 0; index < count; ++index)
    if (std::string_view(name) == entries[index].name) return Value::descriptor(entries[index].descriptor);
  return {};
}

inline Value reflectionResolveEnum(Heap& heap, const Value& value, const EnumReflectionEntry* entries, std::size_t count) {
  if (value.kind() == ValueKind::Null) throw ThrownValue(heap, Value::string("Null Access"));
  const auto& name = value.asString();
  for (std::size_t index = 0; index < count; ++index)
    if (std::string_view(name) == entries[index].name) return Value::enumDescriptor(entries[index].descriptor);
  return {};
}

}
