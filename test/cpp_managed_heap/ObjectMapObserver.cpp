#include "Generated.hpp"
#include <iostream>
#include <stdexcept>

// Once caller roots leave, the map must retain named instance keys and their
// fields exactly as it retains anonymous keys. A back-edge must not leak either.
static void namedKeyGraph() {
  using namespace hxhx::managed;
  static const ClassDescriptor keyLayout{"Key", true, 2, nullptr};
  static const InstanceDescriptor keyApplication{keyLayout};
  Heap heap(0);
  Root<Ref<ObjectMapPayload>> map(heap);
  Root<Ref<InstancePayload>> key(heap);
  heap.allocateInto(map);
  heap.allocateInto(key, keyApplication, std::vector<Value>{Value::integer(7), Value{}});
  const auto identity = ErasedRef(key.get());
  map.get()->insert(identity, Value::string("stored"));
  key.get()->write(keyLayout, 1, Value::managed(map.get()));
  key.set({});
  heap.collect();
  if (heap.liveCount() != 2 || identity.as<InstancePayload>()->read(keyLayout, 0).asInteger() != 7
      || map.get()->readExisting(identity).asString() != "stored")
    throw std::runtime_error("object map failed to trace named instance keys");
  heap.allocateInto(key, keyApplication, std::vector<Value>{Value::integer(7), Value{}});
  if (map.get()->contains(ErasedRef(key.get())))
    throw std::runtime_error("equal named-instance fields replaced allocation identity");
  key.set({});
  map.set({});
  heap.collect();
  if (heap.liveCount() != 0) throw std::runtime_error("named-key map cycle leaked");
}

// Only the map roots the keys and stored arrays after the factory record leaves.
int main() {
  namedKeyGraph();
  using namespace hxhx::managed;
  Heap heap(0);
  Root<Value> result(heap);
  generated_object_map(heap, result, Value{});
  auto record = result.get().asManaged().as<RecordPayload>();
  const auto first = record->read("first").asManaged();
  const auto second = record->read("second").asManaged();
  Root<Value> mapRoot(heap, record->read("map"));
  result.set({});
  heap.collect();
  const auto map = mapRoot.get().asManaged().as<ObjectMapPayload>();
  if (heap.liveCount() != 6 || map->size() != 3 || first == second)
    throw std::runtime_error("object map lost distinct traced keys or replacement semantics");
  if (first.as<RecordPayload>()->read("id").asInteger() != 7 || second.as<RecordPayload>()->read("id").asInteger() != 7)
    throw std::runtime_error("object map did not retain its keys");
  std::cout << "true\n";
  std::cout << map->readExisting(first).asManaged().as<ArrayPayload>()->read(0).asInteger() << '\n';
  std::cout << map->readExisting(second).asManaged().as<ArrayPayload>()->read(0).asInteger() << '\n';
  {
    Root<Ref<RecordPayload>> unrelated(heap);
    heap.allocateInto(unrelated);
    unrelated.get()->define("id", Value::integer(7));
    std::cout << (map->contains(ErasedRef(unrelated.get())) ? "false\n" : "true\n");
  }
  std::cout << map->readExisting(ErasedRef{}).asManaged().as<ArrayPayload>()->read(0).asInteger() << '\n';
  // Add a cycle using the physical storage API; dropping the sole external root
  // must reclaim the map, its keys, and its values together.
  first.as<RecordPayload>()->define("back", mapRoot.get());
  mapRoot.set({});
  heap.collect();
  if (heap.liveCount() != 0) throw std::runtime_error("object map retained unreachable keys or values");
}
