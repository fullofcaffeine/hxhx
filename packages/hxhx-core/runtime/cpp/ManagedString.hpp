#pragma once

#include "ManagedCallable.hpp"
#include <cmath>
#include <iomanip>
#include <locale>
#include <sstream>

namespace hxhx::managed {

// Decode one scalar from the UTF-8 storage used by authored String literals and
// native string operations. Embedded zeroes are characters, not terminators.
// Malformed foreign bytes must be decoded at their input boundary; they cannot
// silently become a different indexing scheme here.
struct StringScalar {
  std::size_t bytes;
  std::uint32_t value;
};

inline StringScalar stringScalar(const std::string& text, std::size_t offset) {
  const auto lead = static_cast<unsigned char>(text.at(offset));
  if (lead < 0x80) return {1, lead};
  const std::size_t count = lead >= 0xc2 && lead <= 0xdf ? 2 :
                            lead >= 0xe0 && lead <= 0xef ? 3 :
                            lead >= 0xf0 && lead <= 0xf4 ? 4 : 0;
  if (count == 0 || count > text.size() - offset)
    throw std::invalid_argument("substring requires valid UTF-8 storage");
  std::uint32_t value = lead & (0x7f >> count);
  for (std::size_t index = 1; index < count; ++index) {
    const auto byte = static_cast<unsigned char>(text[offset + index]);
    if ((byte & 0xc0) != 0x80) throw std::invalid_argument("substring requires valid UTF-8 storage");
    value = (value << 6) | (byte & 0x3f);
  }
  const std::uint32_t minimum = count == 2 ? 0x80 : count == 3 ? 0x800 : 0x10000;
  if (value < minimum || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff))
    throw std::invalid_argument("substring requires valid UTF-8 storage");
  return {count, value};
}

// Native Haxe 4.3.7 counts UTF-16 units, despite our UTF-8 storage. A slice that
// cuts a surrogate pair contains U+FFFD for that half, as independently observed
// before byte conversion. Full scalars retain their exact bytes. The bounds use
// wide arithmetic so INT_MIN/INT_MAX never cause signed C++ overflow.
inline Value stringSubstr(const Value& receiver, const Value& position, const Value& length) {
  const std::string empty;
  const auto& text = receiver.kind() == ValueKind::Null ? empty : receiver.asString();
  std::int64_t size = 0;
  for (std::size_t byte = 0; byte < text.size();) {
    const auto scalar = stringScalar(text, byte);
    size += scalar.value > 0xffff ? 2 : 1;
    byte += scalar.bytes;
  }
  std::int64_t start = position.kind() == ValueKind::Null ? 0 : position.asInteger();
  if (start < 0) start = std::max<std::int64_t>(0, size + start);
  if (start >= size) return Value::string("");
  std::int64_t count = length.kind() == ValueKind::Null ? size : length.asInteger();
  // Native negative lengths count from the complete string's end. Its boundary
  // rule returns empty when the adjusted range reaches that end exactly.
  if (count < 0) {
    count += size;
    if (start + count >= size) return Value::string("");
  }
  if (count <= 0) return Value::string("");
  const auto end = start + std::min(count, size - start);
  std::string result;
  std::int64_t unit = 0;
  for (std::size_t byte = 0; byte < text.size() && unit < end;) {
    const auto scalar = stringScalar(text, byte);
    const auto next = unit + (scalar.value > 0xffff ? 2 : 1);
    if (next > start) {
      if (unit >= start && next <= end) result.append(text, byte, scalar.bytes);
      else result.append("\xef\xbf\xbd", 3);
    }
    byte += scalar.bytes;
    unit = next;
  }
  return Value::string(std::move(result));
}

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
