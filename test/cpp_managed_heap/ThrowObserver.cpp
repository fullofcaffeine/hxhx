#include "Generated.hpp"
#include <exception>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <type_traits>

using namespace hxhx::managed;

// This destructor runs after all generated operand roots have unwound.
struct CollectOnExit {
  Heap& heap;
  ~CollectOnExit() noexcept { heap.collect(); }
};

static void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

static int operandCalls = 0;
static void observeOperand(Heap& heap, ErasedRef, Root<Value>& result) {
  heap.collect();
  result.set(Value::integer(++operandCalls));
}

static void failingOperand(Heap&, ErasedRef, Root<Value>&) {
  throw std::runtime_error("native operand failure");
}

int main() {
  static_assert(std::is_nothrow_copy_constructible_v<ThrownValue>);
  static_assert(std::is_nothrow_copy_assignable_v<ThrownValue>);
  Heap heap(0);
  bool caught = false;
  try {
    CollectOnExit cleanup{heap};
    generated_text(heap);
  } catch (const ThrownValue& error) {
    caught = true;
    require(error.value().kind() == ValueKind::String && error.value().asString() == "problem", "throw changed String");
  }
  require(caught, "String did not throw");
  caught = false;
  try {
    CollectOnExit cleanup{heap};
    generated_integer(heap);
  } catch (const ThrownValue& error) {
    caught = true;
    require(error.value().kind() == ValueKind::Integer && error.value().asInteger() == 7, "throw changed Int");
  }
  require(caught, "Int did not throw");

  std::optional<ThrownValue> retained;
  std::exception_ptr pending;
  try {
    CollectOnExit cleanup{heap};
    generated_array(heap);
  } catch (const ThrownValue& error) {
    retained.emplace(error);
    pending = std::current_exception();
  }
  require(retained.has_value(), "Array did not throw");
  heap.collect();
  const auto identity = retained->value().asManaged().allocationId();
  auto array = retained->value().asManaged().as<ArrayPayload>();
  require(array->size() == 2 && array->read(0).asInteger() == 1, "unwinding lost Array payload");
  array->write(1, Value::integer(9));
  retained.reset();
  heap.collect();
  try {
    std::rethrow_exception(pending);
  } catch (const ThrownValue& error) {
    require(error.value().asManaged().allocationId() == identity, "rethrow changed allocation");
    require(error.value().asManaged().as<ArrayPayload>()->read(1).asInteger() == 9, "rethrow copied payload");
    try {
      throw;
    } catch (const ThrownValue& again) {
      require(&again.value() == &error.value(), "bare rethrow replaced transport state");
    }
  }
  pending = {};
  heap.collect();
  require(heap.liveCount() == 0, "exception retention leaked Array");

  try {
    CollectOnExit cleanup{heap};
    generated_callback(heap);
  } catch (const ThrownValue& error) {
    retained.emplace(error);
  }
  require(retained.has_value(), "callback did not throw");
  heap.collect();
  {
    ActiveCall<void(Root<Value>&)> call(heap, retained->value().asManaged().as<CallablePayload<void(Root<Value>&)>>());
    retained.reset();
    heap.collect();
    Root<Value> returned(heap);
    call.invoke(returned);
    require(returned.get().asInteger() == 1, "throw lost captured mutable cell");
    call.invoke(returned);
    require(returned.get().asInteger() == 2, "throw lost captured mutable cell");
  }
  heap.collect();
  require(heap.liveCount() == 0, "exception retention leaked callback storage");
  try {
    CollectOnExit cleanup{heap};
    generated_throwingCallback(heap);
  } catch (const ThrownValue& error) {
    retained.emplace(error);
  }
  require(retained.has_value(), "throwing callback did not escape");
  caught = false;
  try {
    CollectOnExit cleanup{heap};
    ActiveCall<void(Root<Value>&)> call(heap, retained->value().asManaged().as<CallablePayload<void(Root<Value>&)>>());
    retained.reset();
    Root<Value> returned(heap);
    call.invoke(returned);
  } catch (const ThrownValue& error) {
    caught = true;
    require(error.value().asInteger() == 11, "closure throw changed its operand");
  }
  require(caught, "closure body did not throw");
  heap.collect();
  require(heap.liveCount() == 0, "closure throw leaked storage");

  {
    Root<Ref<CallablePayload<void(Root<Value>&)>>> callback(heap);
    heap.allocateInto(callback, &observeOperand, ErasedRef());
    Root<Value> argument(heap, Value::managed(callback.get()));
    caught = false;
    try {
      CollectOnExit cleanup{heap};
      generated_operand(heap, argument.get());
    } catch (const ThrownValue& error) {
      caught = true;
      require(error.value().asInteger() == 1, "throw operand returned another value");
    }
    require(caught && operandCalls == 1, "throw operand did not run exactly once");
  }
  heap.collect();
  require(heap.liveCount() == 0, "throw operand leaked callable storage");
  {
    Root<Ref<CallablePayload<void(Root<Value>&)>>> callback(heap);
    heap.allocateInto(callback, &failingOperand, ErasedRef());
    Root<Value> argument(heap, Value::managed(callback.get()));
    caught = false;
    try {
      generated_operand(heap, argument.get());
    } catch (const std::runtime_error& error) {
      caught = true;
      require(std::string(error.what()) == "native operand failure", "native failure changed");
    }
    require(caught, "native failure was converted to a source exception");
  }
  heap.collect();
  require(heap.liveCount() == 0 && heap.rootCount() == 0, "exception work retained roots or managed storage");
  std::cout << "CPP_MANAGED_THROW_NATIVE:PASS\n";
}
