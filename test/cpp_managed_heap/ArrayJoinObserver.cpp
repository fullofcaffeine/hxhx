#define main generated_main
#include HXHX_LOCAL_PROGRAM
#undef main
#include "JoinBoundary.hpp"
#include <stdexcept>
#include <string>

using namespace hxhx::managed;
static std::string events;
static int mode = 0;

// The returned allocation has no observer root after return. Only generated
// operand storage can keep it alive across the collecting separator callback.
static void receiver(Heap& heap, ErasedRef, Root<Value>& result) {
  events += 'r';
  if (mode == 1) throw std::runtime_error("receiver");
  if (mode == 3) { result.set(Value{}); return; }
  Root<Ref<ArrayPayload>> array(heap);
  heap.allocateInto(array, ArrayRepresentation::Integer);
  array.get()->append(Value::integer(1));
  array.get()->append(Value::integer(2));
  result.set(Value::managed(array.get()));
}
static void separator(Heap& heap, ErasedRef, Root<Value>& result) {
  events += 's';
  heap.collect();
  if (mode == 2) throw std::runtime_error("separator");
  result.set(Value::string(":"));
}

int main() {
  Heap heap(0);
  hxhx_program_run(heap);
  {
    Root<Ref<CallablePayload<void(Root<Value>&)>>> values(heap), between(heap);
    heap.allocateInto(values, &receiver, ErasedRef{});
    heap.allocateInto(between, &separator, ErasedRef{});
    for (mode = 0; mode != 4; ++mode) {
      events.clear();
      std::string error;
      try {
        Root<Value> result(heap);
        observeArrayJoin(heap, result, Value::managed(values.get()), Value::managed(between.get()));
        if (mode != 0 || result.get().asString() != "1:2") throw std::runtime_error("unexpected join result");
      } catch (const std::exception& failure) { error = failure.what(); }
      const std::string expected = mode == 0 ? "" : mode == 1 ? "receiver" : mode == 2 ? "separator" : "array join has no array";
      if (error != expected || events != (mode == 1 || mode == 3 ? "r" : "rs") || heap.rootCount() != 2)
        throw std::runtime_error("join changed operand effects, failures, or root lifetime");
      heap.collect();
      if (heap.liveCount() != 3) throw std::runtime_error("join retained its temporary receiver");
    }
  }
  heap.collect();
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 1)
    throw std::runtime_error("join retained temporary storage");
}
