#include "Generated.hpp"
#include <iostream>
#include <stdexcept>

// Force tracing during construction, then retain the replaced entries' final
// closures after releasing their owning map. No borrowed entry survives a call.
int main() {
  using namespace hxhx::managed;
  Heap heap(0);
  Root<Value> result(heap);
  generated_collect(heap, result);
  heap.collect();
  auto map = result.get().asManaged().as<IntMapPayload>();
  if (map->size() != 2) throw std::runtime_error("replacement added a duplicate key");
  Root<Value> zero(heap, map->readExisting(0));
  Root<Value> one(heap, map->readExisting(1));
  result.set({});
  heap.collect();
  {
    using Function = CallablePayload<void(Root<Value>&)>;
    ActiveCall<void(Root<Value>&)> first(heap, zero.get().asManaged().as<Function>());
    ActiveCall<void(Root<Value>&)> second(heap, one.get().asManaged().as<Function>());
    Root<Value> returned(heap);
    first.invoke(returned);
    const auto firstValue = returned.get().asInteger();
    second.invoke(returned);
    if (firstValue != 2 || returned.get().asInteger() != 3)
      throw std::runtime_error("map replacement retained the wrong captured value");
  }
  zero.set({});
  one.set({});
  heap.collect();
  if (heap.liveCount() != 0) throw std::runtime_error("map replacement leaked traced storage");
  generated_strings(heap, result);
  heap.collect();
  auto strings = result.get().asManaged().as<StringMapPayload>();
  if (strings->size() != 2) throw std::runtime_error("string replacement added a duplicate key");
  zero.set(strings->readExisting("b"));
  one.set(strings->readExisting("a"));
  result.set({});
  heap.collect();
  {
    using Function = CallablePayload<void(Root<Value>&)>;
    ActiveCall<void(Root<Value>&)> first(heap, zero.get().asManaged().as<Function>());
    ActiveCall<void(Root<Value>&)> second(heap, one.get().asManaged().as<Function>());
    Root<Value> returned(heap);
    first.invoke(returned);
    const auto firstValue = returned.get().asInteger();
    second.invoke(returned);
    if (firstValue != 2 || returned.get().asInteger() != 3)
      throw std::runtime_error("string replacement retained the wrong captured value");
  }
  zero.set({});
  one.set({});
  heap.collect();
  if (heap.liveCount() != 0) throw std::runtime_error("string replacement leaked traced storage");
  std::cout << "SOURCE_MAP_CAPTURE_NATIVE:PASS\n";
}
