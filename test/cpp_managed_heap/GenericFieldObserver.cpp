// The authored program retains one Box<Payload>. Its payload is reachable only
// through the generic field; both allocations must disappear after release.
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
  const auto payload = box->read(box->descriptor(), 0).asManaged().as<InstancePayload>();
  if (payload->read(payload->descriptor(), 0).asInteger() != 9
      || heap.liveCount() != 3 || heap.rootCount() != 0 || heap.staticRootCount() != 1)
    throw std::runtime_error("generic field did not retain exactly its live payload");
  statics->field_0.write(Value{});
  heap.collect();
  if (heap.liveCount() != 1 || heap.rootCount() != 0)
    throw std::runtime_error("released generic field kept its instance or payload alive");
}
