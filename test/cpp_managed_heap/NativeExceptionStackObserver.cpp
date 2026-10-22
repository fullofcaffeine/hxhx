#define main hxhx_fixture_main
#include "src/ExceptionMain.cpp"
#undef main
#include "src/ManagedStack.hpp"
#include "Bindings.hpp"
#include <stdexcept>

using namespace hxhx::managed;
static void require(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}

int main() {
  Heap heap(0);
  bool caught = false;
  try { hxhx_program_run(heap); }
  catch (const ThrownValue& thrown) {
    heap.collect();
    require(thrown.value().asString() == "first", "throw changed the payload");
    caught = true;
  }
  require(caught, "authored main did not throw");
  const auto storage = heap.requireStatic<hxhx_statics_program>();
  // Canonical static order: chooseSecond, initial, then StackItem.CFunction.
  require(storage->field_1.read().asManaged().as<StackSnapshotPayload>()->frames().empty(),
          "initial exception stack was not empty");
  require(storage->stack.capture().empty(), "native unwind retained active source frames");
  {
    Root<Value> first(heap);
    HXHX_OBSERVE_STACK(heap, first);
    heap.collect();
    const auto original = first.get().asManaged().as<StackSnapshotPayload>();
#if HXHX_EXPECT_STACK
    require(original->frames().size() == 2 && original->frames()[0].method == "origin"
            && original->frames()[1].method == "main", "exception capture used the reader's current frames");
#else
    require(original->frames().empty(), "release throw unexpectedly recorded frames");
#endif
    caught = false;
    try { HXHX_SECOND_THROW(heap); }
    catch (const ThrownValue& thrown) {
      heap.collect();
      require(thrown.value().asString() == "second", "second throw changed the payload");
      caught = true;
    }
    require(caught, "second authored method did not throw");
    Root<Value> second(heap);
    HXHX_OBSERVE_STACK(heap, second);
    heap.collect();
    const auto replacement = second.get().asManaged().as<StackSnapshotPayload>();
#if HXHX_EXPECT_STACK
    require(replacement->frames().size() == 1 && replacement->frames()[0].method == "secondary",
            "last-exception state did not advance to the new throw site");
    require(original->frames().size() == 2 && original->frames()[0].method == "origin",
            "new throw changed an earlier returned snapshot");
#else
    require(replacement->frames().empty(), "release exception stack acquired frames");
#endif
    require(storage->stack.capture().empty(), "observation retained active method frames");
  }
  storage->field_1.write(Value{});
  heap.collect();
  require(heap.rootCount() == 0 && heap.staticRootCount() == 1 && heap.liveCount() == 2,
          "exception snapshots or carriers survived their last roots");
}
