#include "Generated.hpp"
#include <iostream>
#include <stdexcept>

// Observe generated functions through rooted results, with collection at every
// managed allocation. Never keep an entry reference across source callbacks.
int main() {
  using namespace hxhx::managed;
  Heap heap(0);
  Root<Value> result(heap);
  auto release = [&]() {
    result.set({});
    heap.collect();
    if (heap.liveCount() != 0) throw std::runtime_error("map construction leaked managed storage");
  };
  generated_plain(heap, result);
  heap.collect();
  auto plain = result.get().asManaged().as<IntMapPayload>();
  if (plain->size() != 2 || plain->readExisting(1).asInteger() != 2 || plain->readExisting(2).asInteger() != 3)
    throw std::runtime_error("plain map changed entries");
  release();
  generated_duplicates(heap, result);
  auto duplicate = result.get().asManaged().as<IntMapPayload>();
  if (duplicate->size() != 2 || duplicate->readExisting(0).asInteger() != 2 || duplicate->readExisting(1).asInteger() != 3)
    throw std::runtime_error("duplicate key did not replace its value");
  release();
  generated_guarded(heap, result);
  auto guarded = result.get().asManaged().as<IntMapPayload>();
  if (guarded->size() != 2 || guarded->contains(13) || guarded->contains(23)
      || guarded->readExisting(14).asInteger() != 4 || guarded->readExisting(24).asInteger() != 4)
    throw std::runtime_error("nested map guard changed entries");
  release();
  generated_effects(heap, result);
  auto effects = result.get().asManaged().as<IntMapPayload>();
  if (effects->size() != 2 || effects->readExisting(1).asInteger() != 19 || effects->readExisting(192).asInteger() != 1929)
    throw std::runtime_error("map key/value order changed");
  release();
  generated_captures(heap, result);
  heap.collect();
  auto captured = result.get().asManaged().as<IntMapPayload>();
  Root<Value> first(heap, captured->readExisting(1));
  Root<Value> second(heap, captured->readExisting(2));
  result.set({});
  heap.collect();
  {
    using Function = CallablePayload<void(Root<Value>&)>;
    ActiveCall<void(Root<Value>&)> left(heap, first.get().asManaged().as<Function>());
    ActiveCall<void(Root<Value>&)> right(heap, second.get().asManaged().as<Function>());
    Root<Value> returned(heap);
    left.invoke(returned);
    const auto leftValue = returned.get().asInteger();
    right.invoke(returned);
    if (leftValue != 1 || returned.get().asInteger() != 2)
      throw std::runtime_error("map closures lost distinct iteration bindings");
  }
  first.set({});
  second.set({});
  release();
  generated_strings(heap, result);
  heap.collect();
  auto strings = result.get().asManaged().as<StringMapPayload>();
  if (strings->size() != 2 || strings->readExisting("a").asInteger() != 2 || strings->readExisting("b").asInteger() != 1)
    throw std::runtime_error("string key map changed entries");
  release();
  std::cout << "SOURCE_MAP_COMPREHENSION_NATIVE:PASS\n";
}
