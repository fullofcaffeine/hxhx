#include "ManagedValue.hpp"
#include <iostream>
#include <stdexcept>

using namespace hxhx::managed;

static void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

static const EnumConstructorDescriptor choiceConstructors[] = {{"Empty", 0}, {"Carry", 1}};
static const EnumConstructorDescriptor otherConstructors[] = {{"Empty", 0}};
static const EnumDescriptor choice{"example.Choice", choiceConstructors, 2};
static const EnumDescriptor other{"example.Other", otherConstructors, 1};

static void observe(std::size_t budget) {
  Heap heap(budget);
  Root<Ref<EnumPayload>> empty(heap);
  Root<Ref<EnumPayload>> otherEmpty(heap);
  heap.allocateInto(empty, choice, 0, std::vector<Value>{});
  heap.allocateInto(otherEmpty, other, 0, std::vector<Value>{});
  require(&empty.get()->descriptor() == &choice && &otherEmpty.get()->descriptor() == &other,
          "same constructor name merged distinct enum descriptors");
  require(empty.get()->constructorIndex() == 0 && empty.get()->size() == 0,
          "nullary constructor acquired a payload or wrong tag");

  Root<Ref<ArrayPayload>> values(heap);
  heap.allocateInto(values, ArrayRepresentation::Integer);
  values.get()->append(Value::integer(7));
  Root<Ref<EnumPayload>> payload(heap);
  heap.allocateInto(payload, choice, 1, std::vector<Value>{Value::managed(values.get())});
  values.get()->append(Value::managed(payload.get()));
  Root<Value> erased(heap, Value::managed(payload.get()));
  const auto identity = payload.get().allocationId();
  payload.set({});
  values.set({});
  heap.collect();
  require(heap.liveCount() == 4, "erased enum failed to trace its array cycle");
  const auto recovered = erased.get().asManaged().as<EnumPayload>();
  require(recovered.allocationId() == identity && recovered->constructorIndex() == 1,
          "erasure changed enum allocation identity or tag");
  require(recovered->read(0).asManaged().as<ArrayPayload>()->read(0).asInteger() == 7,
          "collection lost the enum payload");
  bool rejected = false;
  try { (void)recovered->read(1); } catch (const std::out_of_range&) { rejected = true; }
  require(rejected, "enum payload read accepted an invalid index");
  erased.set({});
  heap.collect();
  require(heap.liveCount() == 2, "unreachable enum-array cycle leaked");

  const auto retained = empty.get().allocationId();
  rejected = false;
  try { heap.allocateInto(empty, choice, 2, std::vector<Value>{}); }
  catch (const std::invalid_argument&) { rejected = true; }
  require(rejected && empty.get().allocationId() == retained && heap.liveCount() == 2,
          "invalid constructor tag changed the destination or leaked");
  rejected = false;
  try { heap.allocateInto(empty, choice, 1, std::vector<Value>{}); }
  catch (const std::invalid_argument&) { rejected = true; }
  require(rejected && empty.get().allocationId() == retained && heap.liveCount() == 2,
          "invalid constructor arity changed the destination or leaked");
  empty.set({});
  otherEmpty.set({});
  heap.collect();
  require(heap.liveCount() == 0 && heap.allocationBytes() == 0, "enum storage survived its roots");
}

int main() {
  observe(0);
  observe(1024 * 1024);
  std::cout << "CPP_MANAGED_ENUM:PASS\n";
}
