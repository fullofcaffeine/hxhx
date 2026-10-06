// These slots follow the independently specified declaration order after sorting:
// Main: aInt, bString, cLeaf; Box: count, value; Leaf appends flag.
#define main generated_main
#include "Main.cpp"
#undef main
#include <stdexcept>

int main() {
  using namespace hxhx::managed;
  Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  const auto statics = heap.requireStatic<hxhx_statics_program>();
  const auto ints = statics->field_0.read().asManaged().as<InstancePayload>();
  const auto strings = statics->field_1.read().asManaged().as<InstancePayload>();
  const auto leaf = statics->field_2.read().asManaged().as<InstancePayload>();
  const auto& box = ints->descriptor();
  if (&box != &strings->descriptor() || !leaf->hasOwner(box))
    throw std::runtime_error("generic applications lost nominal class identity");
  for (const auto value : {ints, strings, leaf}) {
    if (value->read(box, 0).asInteger() != 0 || value->read(box, 1).kind() != ValueKind::Null)
      throw std::runtime_error("applied type replaced a declared generic default");
  }
  if (leaf->read(leaf->descriptor(), 2).asBoolean())
    throw std::runtime_error("generic ancestor changed child field offsets");
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 4)
    throw std::runtime_error("generic allocations lost or retained unexpected roots");
  statics->field_0.write(Value{});
  statics->field_1.write(Value{});
  statics->field_2.write(Value{});
  heap.collect();
  if (heap.liveCount() != 1 || heap.rootCount() != 0)
    throw std::runtime_error("generic allocations survived released static references");
}
