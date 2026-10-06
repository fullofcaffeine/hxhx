#include "Generated.hpp"
#include <iostream>
#include <stdexcept>

// Force collection at allocation boundaries, then observe the returned rooted array.
int main() {
  using namespace hxhx::managed;
  Heap heap(0);
  Root<Value> result(heap);
  generated_collect(heap, result);
  heap.collect();
  const auto array = result.get().asManaged().as<ArrayPayload>();
  if (array->size() != 2 || array->read(0).asString() != "a=>b" || array->read(1).asString() != "a=>b")
    throw std::runtime_error("comprehension changed yielded values or iteration count");
  std::cout << array->read(0).asString() << ',' << array->read(1).asString() << '\n';
  result.set({});
  heap.collect();
  if (heap.liveCount() != 0) throw std::runtime_error("comprehension leaked iteration or result storage");
  generated_guarded(heap, result);
  heap.collect();
  const auto guarded = result.get().asManaged().as<ArrayPayload>();
  if (guarded->size() != 2 || guarded->read(0).asInteger() != 12 || guarded->read(1).asInteger() != 23)
    throw std::runtime_error("comprehension guard changed evaluation count or order");
  std::cout << guarded->read(0).asInteger() << ',' << guarded->read(1).asInteger() << '\n';
  result.set({});
  heap.collect();
  if (heap.liveCount() != 0) throw std::runtime_error("guarded comprehension leaked storage");
  generated_chained(heap, result);
  heap.collect();
  const auto chained = result.get().asManaged().as<ArrayPayload>();
  if (chained->size() != 2 || chained->read(0).asInteger() != 132 || chained->read(1).asInteger() != 243)
    throw std::runtime_error("comprehension evaluated a skipped guard or yield");
  std::cout << chained->read(0).asInteger() << ',' << chained->read(1).asInteger() << '\n';
  result.set({});
  heap.collect();
  if (heap.liveCount() != 0) throw std::runtime_error("chained comprehension leaked storage");
  generated_captures(heap, result);
  const auto captured = result.get().asManaged().as<ArrayPayload>();
  if (captured->size() != 2) throw std::runtime_error("comprehension lost captured functions");
  Root<Value> first(heap, captured->read(0));
  Root<Value> second(heap, captured->read(1));
  result.set({});
  heap.collect();
  {
    using Function = CallablePayload<void(Root<Value>&)>;
    ActiveCall<void(Root<Value>&)> a(heap, first.get().asManaged().as<Function>());
    ActiveCall<void(Root<Value>&)> b(heap, second.get().asManaged().as<Function>());
    Root<Value> returned(heap);
    a.invoke(returned);
    const auto left = returned.get().asInteger();
    b.invoke(returned);
    const auto right = returned.get().asInteger();
    if (left != 1 || right != 2) throw std::runtime_error("comprehension reused an iteration capture cell");
    std::cout << left << ',' << right << '\n';
  }
  first.set({});
  second.set({});
  heap.collect();
  if (heap.liveCount() != 0) throw std::runtime_error("comprehension leaked captured cells or environments");
  generated_nested(heap, result);
  heap.collect();
  const auto nested = result.get().asManaged().as<ArrayPayload>();
  if (nested->size() != 4 || nested->read(0).asInteger() != 13 || nested->read(1).asInteger() != 14
      || nested->read(2).asInteger() != 23 || nested->read(3).asInteger() != 24)
    throw std::runtime_error("nested comprehension changed flattening or iteration order");
  std::cout << nested->read(0).asInteger() << ',' << nested->read(1).asInteger() << ','
            << nested->read(2).asInteger() << ',' << nested->read(3).asInteger() << '\n';
  result.set({});
  heap.collect();
  if (heap.liveCount() != 0) throw std::runtime_error("nested comprehension leaked storage");
  generated_early(heap, result);
  heap.collect();
  const auto early = result.get().asManaged().as<ArrayPayload>();
  if (early->size() != 1 || early->read(0).asInteger() != 99)
    throw std::runtime_error("comprehension redirected its function return");
  std::cout << early->read(0).asInteger() << '\n';
  result.set({});
  heap.collect();
  if (heap.liveCount() != 0) throw std::runtime_error("early comprehension return leaked storage");
  generated_exits(heap, result);
  heap.collect();
  const auto exits = result.get().asManaged().as<ArrayPayload>();
  if (exits->size() != 2 || exits->read(0).asInteger() != 1 || exits->read(1).asInteger() != 3)
    throw std::runtime_error("comprehension lost a loop exit or appended a skipped yield");
  std::cout << exits->read(0).asInteger() << ',' << exits->read(1).asInteger() << '\n';
  result.set({});
  heap.collect();
  if (heap.liveCount() != 0) throw std::runtime_error("loop exits leaked comprehension storage");
  generated_indexed(heap, result);
  heap.collect();
  const auto indexed = result.get().asManaged().as<ArrayPayload>();
  if (indexed->size() != 2 || indexed->read(0).asInteger() != 5 || indexed->read(1).asInteger() != 108)
    throw std::runtime_error("key/value comprehension lost its index or element");
  std::cout << indexed->read(0).asInteger() << ',' << indexed->read(1).asInteger() << '\n';
  result.set({});
  heap.collect();
  if (heap.liveCount() != 0) throw std::runtime_error("key/value comprehension leaked storage");
  generated_indexedCaptures(heap, result);
  const auto indexedCaptured = result.get().asManaged().as<ArrayPayload>();
  if (indexedCaptured->size() != 2) throw std::runtime_error("key/value comprehension lost captured functions");
  Root<Value> keyFirst(heap, indexedCaptured->read(0));
  Root<Value> keySecond(heap, indexedCaptured->read(1));
  result.set({});
  heap.collect();
  {
    using Function = CallablePayload<void(Root<Value>&)>;
    ActiveCall<void(Root<Value>&)> a(heap, keyFirst.get().asManaged().as<Function>());
    ActiveCall<void(Root<Value>&)> b(heap, keySecond.get().asManaged().as<Function>());
    Root<Value> returned(heap);
    a.invoke(returned);
    const auto left = returned.get().asInteger();
    b.invoke(returned);
    const auto right = returned.get().asInteger();
    if (left != 5 || right != 108) throw std::runtime_error("key/value capture reused an iteration cell");
    std::cout << left << ',' << right << '\n';
  }
  keyFirst.set({});
  keySecond.set({});
  heap.collect();
  if (heap.liveCount() != 0) throw std::runtime_error("key/value capture leaked cells or environments");

}
