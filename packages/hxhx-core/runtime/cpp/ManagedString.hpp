#pragma once

#include "ManagedCallable.hpp"
#include <cmath>
#include <iomanip>
#include <locale>
#include <sstream>

namespace hxhx::managed {

// Admitted Std.string and enum comparison operations select this formatter.
// The generated callback owns primitive and instance dispatch. Storage provides
// field order; this helper never looks up source types or method declarations.
using StringConversion = void (*)(Heap&, Value, Root<Value>&);

// Native Haxe's independently observed text uses fifteen significant digits.
// Keep signed zero and special values explicit instead of accepting library-
// specific spellings. This operation does not change stored floating-point bits.
inline std::string formatFloatString(double value) {
  if (std::isnan(value)) return "nan";
  if (std::isinf(value)) return value < 0 ? "-inf" : "inf";
  if (value == 0.0) return "0";
  std::ostringstream output;
  output.imbue(std::locale::classic());
  output << std::setprecision(15) << value;
  return output.str();
}

inline std::string convertedStringBytes(const Value& value) {
  if (value.kind() == ValueKind::Null) return "null";
  if (value.kind() != ValueKind::String) throw std::invalid_argument("string conversion returned a non-String value");
  return value.asString();
}

// Keep parent, selected child, callable environment and result live across user
// conversion code. Values are read one at a time so later reads observe edits.
// Publish only the complete result; an exception leaves the caller's root alone.
inline bool formatAggregateString(Heap& heap, Value input, Root<Value>& result, StringConversion convert) {
  if (input.kind() != ValueKind::Managed) return false;
  Root<Value> parent(heap, input);
  Root<Value> child(heap), converted(heap);
  const auto payload = parent.get().asManaged();
  if (payload.hasLayout<EnumPayload>()) {
    const auto value = payload.as<EnumPayload>();
    std::string bytes = value->descriptor().constructors[value->constructorIndex()].name;
    if (value->size() != 0) {
      bytes += "(";
      for (std::size_t index = 0; index < value->size(); ++index) {
        if (index != 0) bytes += ",";
        child.set(value->read(index));
        convert(heap, child.get(), converted);
        bytes += convertedStringBytes(converted.get());
      }
      bytes += ")";
    }
    result.set(Value::string(bytes));
    return true;
  }
  if (payload.hasLayout<ArrayPayload>()) {
    const auto array = payload.as<ArrayPayload>();
    const auto count = array->size();
    std::string bytes = "[";
    for (std::size_t index = 0; index < count; ++index) {
      if (index != 0) bytes += ",";
      child.set(array->read(index));
      convert(heap, child.get(), converted);
      bytes += convertedStringBytes(converted.get());
    }
    result.set(Value::string(bytes + "]"));
    return true;
  }
  using ConversionSignature = void(Root<Value>&);
  if (payload.hasLayout<RecordPayload>()) {
    const auto record = payload.as<RecordPayload>();
    if (record->contains("toString")) {
      child.set(record->read("toString"));
      if (child.get().kind() != ValueKind::Null) {
        if (child.get().kind() != ValueKind::Managed || !child.get().asManaged().hasLayout<CallablePayload<ConversionSignature>>())
          throw std::invalid_argument("record conversion requires a parameterless rooted-result callable");
        ActiveCall<ConversionSignature> call(heap, child.get().asManaged().as<CallablePayload<ConversionSignature>>());
        call.invoke(converted);
        if (converted.get().kind() != ValueKind::Null && converted.get().kind() != ValueKind::String)
          throw std::invalid_argument("record conversion returned a non-String value");
        result.set(converted.get());
        return true;
      }
    }
    const auto names = record->fieldNames();
    std::string bytes = "{";
    for (std::size_t index = 0; index < names.size(); ++index) {
      bytes += index == 0 ? " " : ", ";
      bytes += names[index] + " => ";
      child.set(record->read(names[index]));
      convert(heap, child.get(), converted);
      bytes += convertedStringBytes(converted.get());
    }
    result.set(Value::string(bytes + " }"));
    return true;
  }
  // This exact callable family has an independently observed native spelling.
  // Other signatures remain explicit unsupported cases in the caller.
  if (payload.hasLayout<CallablePayload<ConversionSignature>>()) {
    result.set(Value::string("Object"));
    return true;
  }
  return false;
}

} // namespace hxhx::managed
