#include "Generated.hpp"
#include <iostream>
#include <stdexcept>

using namespace hxhx::managed;
using IntegerEffect = CallablePayload<void(Root<Value>&)>;
using ValueEffect = CallablePayload<void(Root<Value>&)>;

static void require(bool condition) { if (!condition) throw std::runtime_error("static field observer failed"); }
static void eleven(Heap& heap, ErasedRef, Root<Value>& result) { heap.collect(); result.set(Value::integer(11)); }
static void throwingInteger(Heap& heap, ErasedRef, Root<Value>&) { heap.collect(); throw std::runtime_error("source effect"); }
static void array(Heap& heap, ErasedRef, Root<Value>& result) {
  Root<Ref<ArrayPayload>> value(heap);
  heap.allocateInto(value, ArrayRepresentation::Integer);
  value.get()->append(Value::integer(37));
  result.set(Value::managed(value.get()));
}
static void throwingValue(Heap& heap, ErasedRef, Root<Value>&) { heap.collect(); throw std::runtime_error("source value effect"); }

int main() {
  Heap heap(0);
  publishStorage(heap);
  generated_seed(heap, 2);
  std::cout << generated_read(heap) << '\n';
  Root<Value> escaped(heap);
  generated_escaped(heap, escaped);
  generated_seed(heap, 8);
  heap.collect();
  {
    ActiveCall<void(Root<Value>&)> call(heap, escaped.get().asManaged().as<IntegerEffect>());
    Root<Value> returned(heap);
    call.invoke(returned);
    std::cout << returned.get().asInteger() << '\n';
  }
  Root<Ref<IntegerEffect>> effect(heap);
  heap.allocateInto(effect, &eleven, ErasedRef{});
  std::cout << generated_update(heap, Value::managed(effect.get())) << '\n';
  std::cout << generated_read(heap) << '\n';
  std::cout << generated_shadow(heap, 6) << '\n';
  heap.allocateInto(effect, &throwingInteger, ErasedRef{});
  bool failed = false;
  try { generated_update(heap, Value::managed(effect.get())); }
  catch (const std::runtime_error&) { failed = true; }
  require(failed && generated_read(heap) == 29);
  Root<Ref<ValueEffect>> produce(heap);
  heap.allocateInto(produce, &array, ErasedRef{});
  Root<Value> result(heap);
  generated_keep(heap, result, Value::managed(produce.get()));
  const auto retained = result.get().asManaged().allocationId();
  result.set({});
  escaped.set({});
  effect.set({});
  produce.set({});
  heap.collect();
  require(heap.liveCount() == 2); // Program storage and its sole remaining array edge.
  generated_get(heap, result);
  require(result.get().asManaged().allocationId() == retained);
  require(result.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == 37);
  heap.allocateInto(produce, &throwingValue, ErasedRef{});
  result.set({});
  failed = false;
  try { generated_keep(heap, result, Value::managed(produce.get())); }
  catch (const std::runtime_error&) { failed = true; }
  require(failed && result.get().kind() == ValueKind::Null);
  generated_get(heap, result);
  require(result.get().asManaged().allocationId() == retained);
  // Overwriting the static field must release the old array once external roots leave.
  heap.allocateInto(produce, &array, ErasedRef{});
  generated_keep(heap, result, Value::managed(produce.get()));
  require(result.get().asManaged().allocationId() != retained);
  result.set({});
  produce.set({});
  heap.collect();
  require(heap.liveCount() == 2 && heap.staticRootCount() == 1);
  generated_seed(heap, 2);
  require(generated_postIncrement(heap) == 2);
  require(generated_preIncrement(heap) == 4);
  require(generated_postDecrement(heap) == 12);
  require(generated_preDecrement(heap) == 10);
  require(generated_read(heap) == 14);
}
