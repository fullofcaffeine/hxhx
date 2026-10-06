#define main hxhx_fixture_main
#include "src/Main.cpp"
#undef main
#include "src/ManagedStack.hpp"
#include <stdexcept>

using namespace hxhx::managed;

int main() {
  Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  // The source has one field, followed by the real StackItem.CFunction singleton
  // loaded through NativeStackTrace.toHaxe's declaration. Check both roots.
  const auto storage = heap.requireStatic<hxhx_statics_program>();
  const auto saved = storage->field_0.read();
  const auto snapshot = saved.asManaged().as<StackSnapshotPayload>();
  const auto singleton = storage->field_1.read().asManaged().as<EnumPayload>();
  if (std::string(singleton->descriptor().identity) != "haxe.CallStack.StackItem"
      || singleton->constructorIndex() != 0 || heap.liveCount() != 3)
    throw std::runtime_error("stack fixture has an unexpected startup graph");
  const auto& frames = snapshot->frames();
#if HXHX_EXPECT_STACK
  if (frames.size() != 2 || frames[0].owner != "Main" || frames[0].method != "capture"
      || frames[1].owner != "Main" || frames[1].method != "main")
    throw std::runtime_error("generated stack lost source method order");
#else
  if (!frames.empty()) throw std::runtime_error("release build unexpectedly recorded frames");
#endif
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1)
    throw std::runtime_error("stack capture retained an external root");
  if (!storage->stack.capture().empty())
    throw std::runtime_error("generated method exit retained active frames");
  {
    Heap other(0);
    hxhx_program_run(other);
    other.collect();
    const auto independent = other.requireStatic<hxhx_statics_program>()->field_0.read();
    if (independent.asManaged() == saved.asManaged())
      throw std::runtime_error("separate program heaps shared a captured allocation");
    if (snapshot->frames().size() != independent.asManaged().as<StackSnapshotPayload>()->frames().size())
      throw std::runtime_error("another program execution changed frame state");
  }
  storage->field_0.write(Value{});
  heap.collect();
  // Only program storage and StackItem.CFunction remain. The snapshot is gone.
  if (heap.liveCount() != 2)
    throw std::runtime_error("clearing the saved snapshot retained its allocation");
}
