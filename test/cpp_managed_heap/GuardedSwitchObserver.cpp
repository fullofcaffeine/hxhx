#include "Generated.hpp"
#include <iostream>
#include <stdexcept>

using namespace hxhx::managed;
using Getter = void(Root<Value>&);
using Reject = void(Root<Value>&, Value);
static int effects = 0;

static void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

// The callback stores an escaping capture before collecting inside a rejected guard.
static void reject(Heap& heap, ErasedRef environment, Root<Value>& result, Value callback) {
  environment.as<ArrayPayload>()->append(callback);
  heap.collect();
  result.set(Value::boolean(false));
}

// The observed child loses its last container edge. Only generated roots can keep it alive.
static void drop(Heap& heap, ErasedRef environment, Root<Value>& result) {
  environment.as<ArrayPayload>()->write(0, Value());
  heap.collect();
  result.set(Value::boolean(false));
}

static void acceptSecond(Heap& heap, ErasedRef, Root<Value>& result, Value value) {
  effects = effects * 10 + value.asInteger();
  heap.collect();
  result.set(Value::boolean(value.asInteger() == 2));
}

static void runtimeEffect(Heap& heap, ErasedRef, Root<Value>& result, Value value) {
  effects = effects * 10 + value.asInteger();
  heap.collect();
  result.set(Value::boolean(value.asInteger() >= 2));
}

int main() {
  Heap heap(0);
  {
    require(generated_dynamicGuard(heap, Value()) == 0, "null Dynamic guard changed");
    require(generated_dynamicGuard(heap, Value::boolean(false)) == 0, "false Dynamic guard changed");
    require(generated_dynamicGuard(heap, Value::boolean(true)) == 1, "true Dynamic guard changed");
    require(generated_dynamicGuard(heap, Value::integer(0)) == 0, "zero Dynamic guard changed");
    require(generated_dynamicGuard(heap, Value::integer(-1)) == 1, "nonzero Dynamic guard changed");
    require(generated_dynamicGuard(heap, Value::string("true")) == 0, "text became Boolean truth");
    bool rejected = false;
    try { generated_dynamicGuard(heap, Value::floating(0.5)); }
    catch (const std::invalid_argument& error) {
      rejected = std::string(error.what()) == "unsupported Dynamic Float condition conversion";
    }
    require(rejected, "unreviewed Float condition conversion was silently admitted");
    require(generated_scalar(heap, 1) == 12, "guard retry changed scalar selection");
    require(generated_scalar(heap, 2) == 13, "guard retry changed default selection");
    require(generated_loops(heap) == 2, "guarded case changed loop destinations");
    Root<Ref<ArrayPayload>> values(heap), escaped(heap), parent(heap), child(heap);
    heap.allocateInto(values, ArrayRepresentation::Integer);
    values.get()->append(Value::integer(1));
    values.get()->append(Value::integer(2));
    require(generated_observed(heap, Value::managed(values.get())) == 2, "retry reread a mutated element");
    require(values.get()->read(1).asInteger() == 9, "guard mutation was skipped");
    values.get()->write(1, Value::integer(7));
    heap.allocateInto(escaped, ArrayRepresentation::Reference);
    Root<Ref<CallablePayload<Reject>>> rejector(heap);
    heap.allocateInto(rejector, &reject, ErasedRef(escaped.get()));
    Root<Value> selected(heap), result(heap);
    generated_capture(heap, selected, Value::managed(values.get()), Value::managed(rejector.get()));
    values.set({});
    heap.collect();
    {
      ActiveCall<Getter> rejected(heap, escaped.get()->read(0).asManaged().as<CallablePayload<Getter>>());
      rejected.invoke(result);
      require(result.get().asInteger() == 8, "rejected guard lost its escaping capture");
      rejected.invoke(result);
      require(result.get().asInteger() == 9, "captured pattern local lost its mutable cell");
      ActiveCall<Getter> accepted(heap, selected.get().asManaged().as<CallablePayload<Getter>>());
      accepted.invoke(result);
      require(result.get().asInteger() == 7, "separate attempts shared one pattern cell");
    }
    heap.allocateInto(parent, ArrayRepresentation::Reference);
    heap.allocateInto(child, ArrayRepresentation::Integer);
    child.get()->append(Value::integer(23));
    const auto identity = child.get().allocationId();
    parent.get()->append(Value::managed(child.get()));
    child.set({});
    Root<Ref<CallablePayload<Getter>>> dropper(heap);
    heap.allocateInto(dropper, &drop, ErasedRef(parent.get()));
    generated_retained(heap, result, Value::managed(parent.get()), Value::managed(dropper.get()));
    heap.collect();
    require(parent.get()->read(0).kind() == ValueKind::Null, "collecting guard did not mutate its input");
    require(result.get().asManaged().allocationId() == identity, "collecting guard lost a cached observation");
    require(result.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == 23, "cached payload was corrupted");
    generated_nested(heap, selected, 1);
    heap.collect();
    ActiveCall<Getter> nested(heap, selected.get().asManaged().as<CallablePayload<Getter>>());
    nested.invoke(result);
    require(result.get().asInteger() == 12, "nested callable lost guarded control");
    Root<Ref<ArrayPayload>> alternatives(heap), alternativeCaptures(heap);
    heap.allocateInto(alternatives, ArrayRepresentation::Integer);
    alternatives.get()->append(Value::integer(1));
    alternatives.get()->append(Value::integer(2));
    heap.allocateInto(alternativeCaptures, ArrayRepresentation::Reference);
    heap.allocateInto(rejector, &reject, ErasedRef(alternativeCaptures.get()));
    require(generated_alternatives(heap, Value::managed(alternatives.get()), Value::managed(rejector.get())) == 0, "rejected alternatives selected a body");
    require(alternativeCaptures.get()->size() == 2, "OR pattern skipped a matching guard attempt");
    {
      ActiveCall<Getter> first(heap, alternativeCaptures.get()->read(0).asManaged().as<CallablePayload<Getter>>());
      ActiveCall<Getter> second(heap, alternativeCaptures.get()->read(1).asManaged().as<CallablePayload<Getter>>());
      first.invoke(result);
      require(result.get().asInteger() == 2, "first OR attempt lost its own cell");
      second.invoke(result);
      require(result.get().asInteger() == 3, "OR attempts shared a captured cell");
    }
    Root<Ref<RecordPayload>> record(heap);
    heap.allocateInto(record);
    record.get()->define("items", Value::managed(alternatives.get()));
    require(generated_record(heap, Value::managed(record.get())) == 2, "nested record/Array pattern changed selection");
    Root<Ref<CallablePayload<Reject>>> acceptor(heap);
    heap.allocateInto(acceptor, &acceptSecond, ErasedRef{});
    generated_enumValue(heap, selected);
    require(generated_enumSelect(heap, selected.get(), Value::managed(acceptor.get())) == 2, "enum guard did not retry its payload alternative");
    require(effects == 12, "enum payload observation or guard order changed");
    effects = 0;
    require(generated_effectfulTrue(heap, 1, Value::managed(acceptor.get())) == 7, "literal true guard lost its selected return");
    require(generated_effectfulTrue(heap, 2, Value::managed(acceptor.get())) == 9, "unconditional default lost its return");
    require(effects == 1, "literal true guard skipped or repeated its collecting effects");
    heap.allocateInto(acceptor, &runtimeEffect, ErasedRef{});
    effects = 0;
    require(generated_runtimeGuard(heap, 1, Value::managed(acceptor.get())) == 9, "rejected runtime guard lost its default return");
    require(generated_runtimeGuard(heap, 2, Value::managed(acceptor.get())) == 7, "accepted runtime guard lost its nested return");
    require(generated_runtimeGuard(heap, 3, Value::managed(acceptor.get())) == 8, "accepted runtime guard lost its other nested return");
    require(effects == 123, "runtime guard effects changed order");
    effects = 0;
    require(generated_guardThenFallback(heap, 1, Value::managed(acceptor.get())) == 9, "rejected guard did not continue after its switch");
    require(generated_guardThenFallback(heap, 2, Value::managed(acceptor.get())) == 7, "non-exhaustive guard lost its selected return");
    require(effects == 12, "non-exhaustive guard effects changed order");
  }
  heap.collect();
  require(heap.rootCount() == 0 && heap.liveCount() == 0, "guarded control leaked roots or allocations");
  std::cout << "CPP_GUARDED_SWITCH_NATIVE:PASS\n";
}
