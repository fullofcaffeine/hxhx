// A static Box retains its payload and initialized closures. Their captured
// generic local and its payload must disappear when the static root is cleared.
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
  const auto box = statics->field_0.read().asManaged().as<InstancePayload>();
  // Canonical field order is echo, exchange, value in this authored fixture.
  const auto payload = box->read(box->descriptor(), 2).asManaged().as<InstancePayload>();
  if (payload->read(payload->descriptor(), 0).asInteger() != 9
      || heap.liveCount() <= 3 || heap.rootCount() != 0 || heap.staticRootCount() != 1)
    throw std::runtime_error("generic initializer lost its payload or closures");
  statics->field_0.write(Value{});
  heap.collect();
  if (heap.liveCount() != 1 || heap.rootCount() != 0)
    throw std::runtime_error("released generic initializer kept its captured state alive");
}
