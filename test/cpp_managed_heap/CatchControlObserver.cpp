#include "Generated.hpp"
#include <iostream>
#include <stdexcept>

using namespace hxhx::managed;

static void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

int main() {
  Heap heap(0);
  {
    Root<Ref<ArrayPayload>> payload(heap);
    heap.allocateInto(payload, ArrayRepresentation::Integer);
    payload.get()->append(Value::integer(7));
    const auto identity = payload.get().allocationId();
    Root<Value> result(heap);
    generated_any(heap, result, Value::managed(payload.get()));
    heap.collect();
    require(result.get().asManaged().allocationId() == identity, "Any catch lost payload identity");
    generated_select(heap, result, Value::managed(payload.get()));
    heap.collect();
    require(result.get().asManaged().allocationId() == identity, "statement catch lost payload identity");
    generated_expression(heap, result, result.get());
    heap.collect();
    require(result.get().asManaged().allocationId() == identity, "expression catch lost payload identity");
    generated_nested(heap, result, result.get());
    heap.collect();
    require(result.get().asManaged().allocationId() == identity, "nested rethrow lost payload identity");
    generated_select(heap, result, Value());
    require(result.get().kind() == ValueKind::Null, "null catch became unassigned");
    require(generated_loops(heap) == 2, "catch changed the surrounding loop destination");

    Root<Value> inside(heap);
    generated_inside(heap, inside, Value::managed(payload.get()));
    heap.collect();
    {
      ActiveCall<void(Root<Value>&)> call(heap, inside.get().asManaged().as<CallablePayload<void(Root<Value>&)>>());
      call.invoke(result);
      require(result.get().asManaged().allocationId() == identity, "closure handler changed payload identity");
    }
    inside.set(Value());

    Root<Value> first(heap), second(heap);
    generated_capture(heap, first, Value::managed(payload.get()));
    generated_capture(heap, second, Value::integer(9));
    payload.set({});
    heap.collect();
    using Callback = void(Root<Value>&, Value);
    {
      ActiveCall<Callback> call(heap, first.get().asManaged().as<CallablePayload<Callback>>());
      call.invoke(result, Value());
      heap.collect();
      require(result.get().asManaged().allocationId() == identity, "escaped catch closure lost its payload");
      require(result.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == 7, "escaped payload was corrupted");
      call.invoke(result, Value());
      require(result.get().kind() == ValueKind::Null, "catch cell lost its replacement");
    }
    {
      ActiveCall<Callback> call(heap, second.get().asManaged().as<CallablePayload<Callback>>());
      call.invoke(result, Value());
      require(result.get().asInteger() == 9, "separate handler entries shared one cell");
    }
  }
  heap.collect();
  require(heap.rootCount() == 0 && heap.liveCount() == 0, "catch control leaked roots or allocations");
  std::cout << "CPP_CATCH_CONTROL_NATIVE:PASS\n";
}
