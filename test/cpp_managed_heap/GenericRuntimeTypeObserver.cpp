// Force collection before every allocation in the unchanged generated program.
#define main generated_main
#include "Main.cpp"
#undef main
#include <stdexcept>
#include <string>

// Check the public Haxe declaration identity, not merely the allocation count.
static void requireSingleton(const hxhx::managed::Value& value, const char* owner, const char* name) {
  const auto singleton = value.asManaged().as<hxhx::managed::EnumPayload>();
  const auto& descriptor = singleton->descriptor();
  if (std::string(descriptor.identity) != owner || singleton->size() != 0
      || std::string(descriptor.constructors[singleton->constructorIndex()].name) != name)
    throw std::runtime_error("generic runtime fixture retained an unexpected enum constant");
}

int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  // Haxe 4.3.7 declares seven parameterless ValueType constructors and CFunction.
  // Canonical static slots follow Main.evaluations, then these eight constants.
  const auto storage = heap.requireStatic<hxhx_statics_program>();
  if (storage->field_0.read().asInteger() != 2)
    throw std::runtime_error("runtime tests skipped or repeated operand effects");
  requireSingleton(storage->field_1.read(), "Type.ValueType", "TBool");
  requireSingleton(storage->field_2.read(), "Type.ValueType", "TFloat");
  requireSingleton(storage->field_3.read(), "Type.ValueType", "TFunction");
  requireSingleton(storage->field_4.read(), "Type.ValueType", "TInt");
  requireSingleton(storage->field_5.read(), "Type.ValueType", "TNull");
  requireSingleton(storage->field_6.read(), "Type.ValueType", "TObject");
  requireSingleton(storage->field_7.read(), "Type.ValueType", "TUnknown");
  requireSingleton(storage->field_8.read(), "haxe.CallStack.StackItem", "CFunction");
  // Static storage and those constants are the complete persistent graph.
  // Every temporary Inspector, closure, Map, and Payload must be collected.
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 9)
    throw std::runtime_error("runtime tests retained temporary generic operands");
}
