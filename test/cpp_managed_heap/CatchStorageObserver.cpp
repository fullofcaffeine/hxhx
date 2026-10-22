#include "Generated.hpp"
#include <iostream>
#include <stdexcept>

using namespace hxhx::managed;

static void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

static bool failEntry = false;
static void observeCatchEntry(Heap& heap) {
  heap.collect();
  if (failEntry) throw std::runtime_error("catch entry failed");
}

// A native catch supplies a selected value to the production storage emitter.
// This observer tests storage after unwind; it does not implement Haxe matching.
static void enter(Heap& heap, Root<Value>& output, std::int32_t seed) {
  try {
    Root<Ref<ArrayPayload>> payload(heap);
    heap.allocateInto(payload, ArrayRepresentation::Integer);
    payload.get()->append(Value::integer(seed));
    throw ThrownValue(heap, Value::managed(payload.get()));
  } catch (const ThrownValue& thrown) {
    heap.collect();
    Root<Value> selected(heap, thrown.value());
    generatedCatchcapture(heap, output, selected);
  }
}

int main() {
  Heap heap(0);
  {
    Root<Value> first(heap), second(heap), output(heap);
    enter(heap, first, 7);
    enter(heap, second, 9);
    heap.collect();
    require(heap.rootCount() == 3, "native catch retained a transport or temporary root");
    require(heap.liveCount() == 8, "each entry must retain its array, cell, environment and callable");
    {
      ActiveCall<void(Root<Value>&, Value)> call(heap, first.get().asManaged().as<CallablePayload<void(Root<Value>&, Value)>>());
      call.invoke(output, Value::string("replacement"));
      require(output.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == 7, "first catch lost its payload");
      output.set({});
      heap.collect();
      require(heap.liveCount() == 7, "replaced catch payload was retained");
      call.invoke(output, Value{});
      require(output.get().asString() == "replacement", "escaped closure did not update the shared catch cell");
    }
    {
      ActiveCall<void(Root<Value>&, Value)> call(heap, second.get().asManaged().as<CallablePayload<void(Root<Value>&, Value)>>());
      call.invoke(output, Value{});
      require(output.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == 9, "separate handler entries shared a cell");
    }
    first.set({});
    second.set({});
    output.set({});
    heap.collect();
    require(heap.liveCount() == 0, "escaped catch storage leaked after release");
    Root<Ref<ArrayPayload>> array(heap);
    heap.allocateInto(array, ArrayRepresentation::Integer);
    array.get()->append(Value::integer(13));
    first.set(Value::managed(array.get()));
    generatedCatchplain(heap, output, first);
    require(output.get().asManaged().allocationId() == array.get().allocationId(), "uncaptured catch copied its payload");
    require(heap.liveCount() == 1, "uncaptured catch created an unnecessary heap cell");
    first.set({});
    generatedCatchplain(heap, output, first);
    require(output.get().kind() == ValueKind::Null, "null catch value became unassigned");
  }
  heap.collect();
  require(heap.rootCount() == 0 && heap.liveCount() == 0, "catch observer leaked ownership");
  {
    Root<Value> output(heap);
    failEntry = true;
    bool failed = false;
    try { enter(heap, output, 17); }
    catch (const std::runtime_error& error) { failed = std::string(error.what()) == "catch entry failed"; }
    failEntry = false;
    heap.collect();
    require(failed && output.get().kind() == ValueKind::Null, "failed handler published an escaped value");
    require(heap.rootCount() == 1 && heap.liveCount() == 0, "failed entry leaked its captured cell or transport");
  }
  require(heap.rootCount() == 0, "failed-entry observer retained its output root");
  std::cout << "CPP_CATCH_STORAGE_NATIVE:PASS\n";
}
