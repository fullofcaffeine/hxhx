#define main generated_main
#include HXHX_LOCAL_PROGRAM
#undef main
#include "DowncastBoundary.hpp"
#include <stdexcept>
#include <string>

using namespace hxhx::managed;
static int mode = 0;
static std::string events;
static void value(Heap& heap, ErasedRef, Root<Value>& result) {
  events += 'v';
  if (mode == 1) throw std::runtime_error("value");
  if (mode == 3) { result.set(Value{}); return; }
  HXHX_DOWNCAST_VALUE(heap, result);
}
static void target(Heap& heap, ErasedRef, Root<Value>& result) {
  events += 't';
  heap.collect();
  if (mode == 2) throw std::runtime_error("target");
  if (mode == 4) { result.set(Value{}); return; }
  HXHX_DOWNCAST_TARGET(heap, result);
}

// Only generated operand roots retain the temporary source object across the
// target callback's collection. Exceptions must release both operand roots.
int main() {
  Heap heap(0);
  hxhx_program_run(heap);
  {
    Root<Ref<CallablePayload<void(Root<Value>&)>>> values(heap), targets(heap);
    heap.allocateInto(values, &value, ErasedRef{});
    heap.allocateInto(targets, &target, ErasedRef{});
    for (mode = 0; mode != 5; ++mode) {
      events.clear();
      std::string error;
      try {
        Root<Value> result(heap);
        observeDowncast(heap, result, Value::managed(values.get()), Value::managed(targets.get()));
        if ((mode == 0 && result.get().kind() != ValueKind::Managed)
            || (mode >= 3 && result.get().kind() != ValueKind::Null)
            || mode == 1 || mode == 2) throw std::runtime_error("unexpected downcast result");
      } catch (const std::exception& failure) { error = failure.what(); }
      const std::string expected = mode == 1 ? "value" : mode == 2 ? "target" : "";
      if (error != expected || events != (mode == 1 ? "v" : "vt") || heap.rootCount() != 2)
        throw std::runtime_error("downcast lost operand effects, failures, or roots");
      heap.collect();
      if (heap.liveCount() != 3) throw std::runtime_error("downcast retained its temporary source");
    }
  }
  heap.collect();
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 1)
    throw std::runtime_error("downcast retained temporary storage");
}
