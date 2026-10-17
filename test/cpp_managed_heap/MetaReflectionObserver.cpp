// Execute the unchanged metadata program with collection before each allocation.
// Public lookup must return the same static descriptors used by native instances.
#define main generated_main
#include "Main.cpp"
#undef main
#include <stdexcept>

int main() {
  using namespace hxhx::managed;
  Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  const auto box = reflectionResolveClass(heap, Value::string("GenericBox"),
                                         hxhx_reflection_classes.data(), hxhx_reflection_classes.size());
  const auto choice = reflectionResolveEnum(heap, Value::string("MetaChoice"),
                                           hxhx_reflection_enums.data(), hxhx_reflection_enums.size());
  if (box.kind() != ValueKind::Descriptor || choice.kind() != ValueKind::EnumDescriptor
      || !box.asDescriptor()->hasInstanceLayout || box.asDescriptor()->fieldCount != 1)
    throw std::runtime_error("reflection lost the generic class layout or enum identity");
  // In this pinned provider fixture the sorted fields retain SysTools' character
  // array and StringTools' alias. Account for that real startup allocation, and
  // verify it rather than treating every non-enum survivor as a leak.
  const auto statics = heap.requireStatic<hxhx_statics_program>();
  const auto characters = statics->field_10.read().asManaged().as<ArrayPayload>();
  const std::int32_t expected[] = {32, 40, 41, 37, 33, 94, 34, 60, 62, 38, 124, 10, 13, 44, 59};
  if (!(statics->field_1.read().asManaged() == ErasedRef(characters)) || characters->size() != std::size(expected))
    throw std::runtime_error("provider startup lost its shared character array");
  for (std::size_t index = 0; index < std::size(expected); ++index)
    if (characters->read(index).asInteger() != expected[index])
      throw std::runtime_error("provider startup changed a character value");
  std::size_t live = 2; // Static storage and the provider array, plus nullary constructors.
  for (const auto& entry : hxhx_reflection_enums)
    for (std::size_t index = 0; index < entry.descriptor->constructorCount; ++index)
      if (entry.descriptor->constructors[index].arity == 0) ++live;
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != live)
    throw std::runtime_error("metadata lifetime counts: roots=" + std::to_string(heap.rootCount())
        + " statics=" + std::to_string(heap.staticRootCount()) + " live=" + std::to_string(heap.liveCount())
        + " expected=" + std::to_string(live));
  // Same-name metadata from a different program must not borrow a local name.
  static const ClassDescriptor foreign{"Main.GenericBox", false, 0, nullptr};
  bool rejected = false;
  try { (void)reflectionClassName(Value::descriptor(&foreign), hxhx_reflection_classes.data(), hxhx_reflection_classes.size()); }
  catch (const std::invalid_argument&) { rejected = true; }
  if (!rejected) throw std::runtime_error("reflection accepted a foreign class descriptor");
  static const EnumDescriptor foreignEnum{"Main.MetaChoice", nullptr, 0};
  rejected = false;
  try { (void)reflectionEnumName(Value::enumDescriptor(&foreignEnum), hxhx_reflection_enums.data(), hxhx_reflection_enums.size()); }
  catch (const std::invalid_argument&) { rejected = true; }
  if (!rejected) throw std::runtime_error("reflection accepted a foreign enum descriptor");
  // Public names are counted byte strings, not zero-terminated identity tokens.
  const EnumReflectionEntry counted{&foreignEnum, std::string_view("A\0B", 3)};
  const auto countedName = reflectionEnumName(Value::enumDescriptor(&foreignEnum), &counted, 1);
  if (countedName.asString() != std::string("A\0B", 3)
      || reflectionResolveEnum(heap, countedName, &counted, 1).asEnumDescriptor() != &foreignEnum)
    throw std::runtime_error("reflection truncated a counted public name");
  for (bool enumLookup : {false, true}) {
    bool threw = false;
    try {
      if (enumLookup) (void)reflectionResolveEnum(heap, Value{}, hxhx_reflection_enums.data(), hxhx_reflection_enums.size());
      else (void)reflectionResolveClass(heap, Value{}, hxhx_reflection_classes.data(), hxhx_reflection_classes.size());
    } catch (const ThrownValue& error) {
      heap.collect();
      threw = error.value().kind() == ValueKind::String && error.value().asString() == "Null Access";
    }
    if (!threw || heap.rootCount() != 0 || heap.liveCount() != live)
      throw std::runtime_error("null reflection lookup lost its exception or leaked a root");
  }
}
