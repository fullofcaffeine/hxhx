#pragma once
#include <limits>

// Independent observer for emitted Haxe loops. Native callbacks deliberately
// collect and mutate arrays while generated code retains the selected iterable.
namespace managed_iteration_test {
using namespace hxhx::managed;
static unsigned selections = 0;
static unsigned visits = 0;
static bool grow = false;
static bool failVisit = false;

static void require(bool value) {
  if (!value) throw std::runtime_error("managed iteration contract changed");
}

static void source(Heap& heap, ErasedRef environment, Root<Value>& result) {
  ++selections;
  heap.collect();
  result.set(Value::managed(environment));
}

static void freshSource(Heap& heap, ErasedRef, Root<Value>& result) {
  ++selections;
  Root<Ref<ArrayPayload>> created(heap);
  heap.allocateInto(created, ArrayRepresentation::Integer);
  created.get()->append(Value::integer(3));
  created.get()->append(Value::integer(5));
  result.set(Value::managed(created.get()));
}

static void visit(Heap& heap, ErasedRef environment, Value value) {
  ++visits;
  heap.collect();
  if (failVisit) throw std::runtime_error("iteration callback failure");
  if (grow && value.asInteger() == 1) {
    environment.as<ArrayPayload>()->write(1, Value::integer(7));
    environment.as<ArrayPayload>()->append(Value::integer(4));
  }
}

static void save(Heap& heap, ErasedRef environment, Value value) {
  Root<Value> retained(heap, value);
  heap.collect();
  environment.as<ArrayPayload>()->append(retained.get());
}

static void walk(Heap& heap, std::initializer_list<std::int32_t> values,
                 std::int32_t expected, unsigned expectedVisits, bool append) {
  Root<Ref<ArrayPayload>> array(heap);
  heap.allocateInto(array, ArrayRepresentation::Integer);
  for (auto value : values) array.get()->append(Value::integer(value));
  Root<Ref<CallablePayload<void(Root<Value>&)>>> selected(heap);
  heap.allocateInto(selected, &source, ErasedRef(array.get()));
  Root<Ref<CallablePayload<void(Value)>>> effect(heap);
  heap.allocateInto(effect, &visit, ErasedRef(array.get()));
  selections = 0;
  visits = 0;
  grow = append;
  require(generatedIterationwalk(heap, Value::managed(selected.get()), Value::managed(effect.get())) == expected);
  require(selections == 1 && visits == expectedVisits);
}

static void run(Heap& heap) {
  require(generatedIterationnegate(heap, std::numeric_limits<std::int32_t>::min()) == std::numeric_limits<std::int32_t>::min());
  require(generatedIterationnegate(heap, std::numeric_limits<std::int32_t>::max()) == -2147483647);
  require(generatedIterationnegate(heap, 0) == 0);
  walk(heap, {1, 2}, 12, 3, true);
  walk(heap, {-1, 2, 9, 99}, 2, 1, false);
  walk(heap, {}, 0, 0, false);
  failVisit = true;
  bool threw = false;
  try { walk(heap, {1, 2}, 0, 0, false); }
  catch (const std::runtime_error&) { threw = true; }
  failVisit = false;
  require(threw && selections == 1 && visits == 1);
  heap.collect();
  require(heap.liveCount() == 0);
  {
    Root<Ref<CallablePayload<void(Root<Value>&)>>> selected(heap);
    heap.allocateInto(selected, &freshSource, ErasedRef{});
    Root<Ref<CallablePayload<void(Value)>>> effect(heap);
    heap.allocateInto(effect, &visit, ErasedRef{});
    selections = 0;
    visits = 0;
    require(generatedIterationwalk(heap, Value::managed(selected.get()), Value::managed(effect.get())) == 8);
    require(selections == 1 && visits == 2);
  }
  heap.collect();
  require(heap.liveCount() == 0);
  {
    Root<Ref<ArrayPayload>> values(heap);
    heap.allocateInto(values, ArrayRepresentation::Integer);
    values.get()->append(Value::integer(4));
    values.get()->append(Value::integer(6));
    Root<Ref<ArrayPayload>> saved(heap);
    heap.allocateInto(saved, ArrayRepresentation::Reference);
    Root<Ref<CallablePayload<void(Value)>>> receiver(heap);
    heap.allocateInto(receiver, &save, ErasedRef(saved.get()));
    generatedIterationcapture(heap, Value::managed(values.get()), Value::managed(receiver.get()));
    require(saved.get()->size() == 2);
    values.get()->write(0, Value::integer(90));
    values.set({});
    receiver.set({});
    heap.collect();
    ActiveCall<void(Root<Value>&)> first(heap, saved.get()->read(0).asManaged().as<CallablePayload<void(Root<Value>&)>>());
    ActiveCall<void(Root<Value>&)> second(heap, saved.get()->read(1).asManaged().as<CallablePayload<void(Root<Value>&)>>());
    Root<Value> firstResult(heap), secondResult(heap);
    first.invoke(firstResult);
    second.invoke(secondResult);
    require(firstResult.get().asInteger() == 4 && secondResult.get().asInteger() == 6);
    saved.set({});
    heap.collect();
    first.invoke(firstResult);
    second.invoke(secondResult);
    require(firstResult.get().asInteger() == 4 && secondResult.get().asInteger() == 6);
  }
  heap.collect();
  require(heap.liveCount() == 0);
  {
    Root<Ref<ArrayPayload>> left(heap);
    heap.allocateInto(left, ArrayRepresentation::Integer);
    left.get()->append(Value::integer(1));
    left.get()->append(Value::integer(2));
    Root<Ref<ArrayPayload>> right(heap);
    heap.allocateInto(right, ArrayRepresentation::Integer);
    right.get()->append(Value::integer(3));
    right.get()->append(Value::integer(4));
    require(generatedIterationnested(heap, Value::managed(left.get()), Value::managed(right.get())) == 20);
    require(generatedIterationfirst(heap, Value::managed(right.get())) == 3);
    heap.allocateInto(right, ArrayRepresentation::Integer);
    require(generatedIterationfirst(heap, Value::managed(right.get())) == -1);
    bool nullRejected = false;
    try { generatedIterationfirst(heap, Value{}); }
    catch (const std::invalid_argument&) { nullRejected = true; }
    require(nullRejected);
  }
  heap.collect();
  require(heap.liveCount() == 0);
}
} // namespace managed_iteration_test
