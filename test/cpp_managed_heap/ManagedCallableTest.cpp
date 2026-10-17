#include "ManagedCallable.hpp"
#include <iostream>
#include <stdexcept>

using namespace hxhx::managed;
using Counter = CallablePayload<int(int)>;

struct CounterEnvironment {
  Ref<CellPayload> count;
  Ref<CellPayload> self;
  int* destroyed;
  CounterEnvironment(Ref<CellPayload> count, Ref<CellPayload> self, int& destroyed)
      : count(count), self(self), destroyed(&destroyed) {}
  ~CounterEnvironment() noexcept { ++*destroyed; }
};

struct ThrowEnvironment {
  Value self;
  int* destroyed;
  explicit ThrowEnvironment(int& destroyed) : destroyed(&destroyed) {}
  ~ThrowEnvironment() noexcept { ++*destroyed; }
};

struct ReentrantEnvironment {
  Ref<CellPayload> binding;
  Ref<Counter> replacement;
  int* destroyed;
  ReentrantEnvironment(Ref<CellPayload> binding, Ref<Counter> replacement, int& destroyed)
      : binding(binding), replacement(replacement), destroyed(&destroyed) {}
  ~ReentrantEnvironment() noexcept { ++*destroyed; }
};

namespace hxhx::managed {
template<> struct Trace<CounterEnvironment> {
  static void visit(const CounterEnvironment& value, Visitor& visitor) noexcept {
    visitor.mark(value.count);
    visitor.mark(value.self);
  }
};
template<> struct Trace<ThrowEnvironment> {
  static void visit(const ThrowEnvironment& value, Visitor& visitor) noexcept { value.self.trace(visitor); }
};
template<> struct Trace<ReentrantEnvironment> {
  static void visit(const ReentrantEnvironment& value, Visitor& visitor) noexcept {
    visitor.mark(value.binding);
    visitor.mark(value.replacement);
  }
};
}

static void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

static int countEntry(Heap& heap, ErasedRef reference, int remaining) {
  heap.collect();
  const auto environment = reference.as<CounterEnvironment>();
  environment->count->write(Value::integer(environment->count->read().asInteger() + 1));
  if (remaining == 0) return environment->count->read().asInteger();
  ActiveCall<int(int)> recursive(heap, environment->self->read().asManaged().as<Counter>());
  return recursive.invoke(remaining - 1);
}

// Mirrors the selected allocation contract: every intermediate is rooted and
// the caller's result is published before creator roots leave scope.
static void makeCounter(Heap& heap, Root<Ref<Counter>>& result, Root<Ref<CellPayload>>& binding,
                        int& destroyed, CellWriteMode mode) {
  Root<Ref<CellPayload>> count(heap);
  heap.allocateInto(count, CellWriteMode::Replaceable);
  count.get()->write(Value::integer(0));
  heap.allocateInto(binding, mode);
  Root<Ref<CounterEnvironment>> environment(heap);
  heap.allocateInto(environment, count.get(), binding.get(), destroyed);
  heap.allocateInto(result, &countEntry, ErasedRef(environment.get()));
  binding.get()->write(Value::managed(result.get()));
}

static void cellStates() {
  CellPayload once(CellWriteMode::Once);
  require(!once.assigned(), "new cell is already assigned");
  bool failed = false;
  try { static_cast<void>(once.read()); }
  catch (const std::logic_error&) { failed = true; }
  require(failed, "unassigned cell silently projected a source value");
  once.write(Value());
  require(once.assigned() && once.read().kind() == ValueKind::Null, "assigned null lost its presence state");
  failed = false;
  try { once.write(Value::integer(1)); }
  catch (const std::logic_error&) { failed = true; }
  require(failed && once.read().kind() == ValueKind::Null, "write-once cell allowed replacement");
  CellPayload mutableCell(CellWriteMode::Replaceable);
  mutableCell.write(Value::integer(7));
  mutableCell.write(Value());
  require(mutableCell.assigned() && mutableCell.read().kind() == ValueKind::Null, "ordinary replacement lost assigned state");
}

static void recursionAndCopies(std::size_t budget) {
  int destroyed = 0;
  Heap heap(budget);
  Root<Ref<Counter>> counter(heap), copy(heap), independent(heap);
  Root<Ref<CellPayload>> binding(heap), independentBinding(heap);
  makeCounter(heap, counter, binding, destroyed, CellWriteMode::Once);
  copy.set(counter.get());
  makeCounter(heap, independent, independentBinding, destroyed, CellWriteMode::Once);
  binding.set({});
  independentBinding.set({});
  {
    ActiveCall<int(int)> first(heap, counter.get());
    require(first.invoke(2) == 3, "recursive calls do not share their captured state");
    counter.set({});
    ActiveCall<int(int)> second(heap, copy.get());
    require(second.invoke(1) == 5, "copied closure lost shared state");
    ActiveCall<int(int)> other(heap, independent.get());
    require(other.invoke(0) == 1, "independent creator invocation reused a cell");
  }
  copy.set({});
  independent.set({});
  heap.collect();
  require(destroyed == 2 && heap.liveCount() == 0, "recursive self cycles were not released");
}

static int replacementEntry(Heap& heap, ErasedRef, int value) {
  heap.collect();
  return 100 + value;
}

static void activeReplacement(std::size_t budget) {
  int destroyed = 0;
  Heap heap(budget);
  Root<Ref<Counter>> original(heap), replacement(heap);
  Root<Ref<CellPayload>> binding(heap);
  makeCounter(heap, original, binding, destroyed, CellWriteMode::Replaceable);
  heap.allocateInto(replacement, &replacementEntry, ErasedRef());
  {
    // Selection precedes argument effects. Removing the old binding must not
    // invalidate the selected callable, while recursive reads use its new value.
    ActiveCall<int(int)> selected(heap, original.get());
    original.set({});
    binding.get()->write(Value::managed(replacement.get()));
    replacement.set({});
    heap.collect();
    require(destroyed == 0, "argument-side replacement destroyed the active environment");
    require(selected.invoke(2) == 101, "recursive call ignored the current mutable binding");
  }
  heap.collect();
  require(destroyed == 1 && heap.liveCount() == 2, "active call retained the obsolete environment after return");
  binding.set({});
  heap.collect();
  require(heap.liveCount() == 0, "replacement binding leaked");
}

static void arrayResultEntry(Heap& heap, ErasedRef, Root<Value>& result) {
  Root<Ref<ArrayPayload>> array(heap);
  heap.allocateInto(array, ArrayRepresentation::Integer);
  array.get()->append(Value::integer(9));
  result.set(Value::managed(array.get()));
}

static int reentrantEntry(Heap& heap, ErasedRef reference, int value) {
  const auto environment = reference.as<ReentrantEnvironment>();
  environment->binding->write(Value::managed(environment->replacement));
  heap.collect();
  ActiveCall<int(int)> replaced(heap, environment->binding->read().asManaged().as<Counter>());
  return 300 + replaced.invoke(value);
}

static void replacementDuringInvocation(std::size_t budget) {
  int destroyed = 0;
  Heap heap(budget);
  Root<Ref<CellPayload>> binding(heap);
  {
    Root<Ref<Counter>> original(heap), replacement(heap);
    Root<Ref<ReentrantEnvironment>> environment(heap);
    heap.allocateInto(binding, CellWriteMode::Replaceable);
    heap.allocateInto(replacement, &replacementEntry, ErasedRef());
    heap.allocateInto(environment, binding.get(), replacement.get(), destroyed);
    heap.allocateInto(original, &reentrantEntry, ErasedRef(environment.get()));
    binding.get()->write(Value::managed(original.get()));
    ActiveCall<int(int)> selected(heap, original.get());
    original.set({});
    replacement.set({});
    environment.set({});
    require(selected.invoke(1) == 401 && destroyed == 0, "replacement during invocation lost the active environment");
  }
  heap.collect();
  require(destroyed == 1 && heap.liveCount() == 2, "completed invocation retained its obsolete environment");
  binding.set({});
  heap.collect();
  require(heap.liveCount() == 0, "reentrant replacement leaked");
}

static void argumentEntry(Heap& heap, ErasedRef, Root<Value>& result, Value argument, Root<Value>& source) {
  Root<Value> parameter(heap, std::move(argument));
  source.set({});
  heap.collect();
  result.set(parameter.get());
}

static void rootedParameter(std::size_t budget) {
  Heap heap(budget);
  Root<Value> input(heap), result(heap);
  Root<Ref<CallablePayload<void(Root<Value>&, Value, Root<Value>&)>>> callable(heap);
  {
    Root<Ref<ArrayPayload>> array(heap);
    heap.allocateInto(array, ArrayRepresentation::Integer);
    array.get()->append(Value::integer(17));
    input.set(Value::managed(array.get()));
  }
  heap.allocateInto(callable, &argumentEntry, ErasedRef());
  {
    ActiveCall<void(Root<Value>&, Value, Root<Value>&)> selected(heap, callable.get());
    selected.invoke(result, input.get(), input);
  }
  callable.set({});
  heap.collect();
  require(input.get().kind() == ValueKind::Null && result.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == 17,
          "parameter ingress did not survive caller storage replacement");
  result.set({});
  heap.collect();
  require(heap.liveCount() == 0, "parameter or result root leaked");
}

static void throwingEntry(Heap& heap, ErasedRef) {
  heap.collect();
  throw std::runtime_error("callback failed");
}

static void resultAndUnwind(std::size_t budget) {
  int destroyed = 0;
  Heap heap(budget);
  Root<Value> result(heap);
  {
    Root<Ref<CallablePayload<void(Root<Value>&)>>> factory(heap);
    heap.allocateInto(factory, &arrayResultEntry, ErasedRef());
    ActiveCall<void(Root<Value>&)> selected(heap, factory.get());
    factory.set({});
    selected.invoke(result);
  }
  heap.collect();
  require(heap.liveCount() == 1 && result.get().asManaged().as<ArrayPayload>()->read(0).asInteger() == 9,
          "return handoff lost the callee's managed result");
  result.set({});
  heap.collect();
  const auto rootsBefore = heap.rootCount();
  bool failed = false;
  try {
    Root<Ref<ThrowEnvironment>> environment(heap);
    Root<Ref<CallablePayload<void()>>> callable(heap);
    heap.allocateInto(environment, destroyed);
    heap.allocateInto(callable, &throwingEntry, ErasedRef(environment.get()));
    environment.get()->self = Value::managed(callable.get());
    ActiveCall<void()> selected(heap, callable.get());
    environment.set({});
    callable.set({});
    selected.invoke();
  } catch (const std::runtime_error&) { failed = true; }
  require(failed && heap.rootCount() == rootsBefore, "callback unwind leaked its active root");
  heap.collect();
  require(destroyed == 1 && heap.liveCount() == 0, "callback unwind retained its cycle");
}

int main() {
  cellStates();
  {
    Heap heap;
    bool failed = false;
    int effects = 0;
    try {
      ActiveCall<int(int)> absent(heap, Ref<Counter>());
      require(heap.rootCount() == 1, "null selection lost its registered root");
      absent.invoke(++effects);
    }
    catch (const std::invalid_argument&) { failed = true; }
    require(failed && effects == 1 && heap.rootCount() == 0, "null invocation skipped argument effects or leaked its root");
    Root<Ref<Counter>> absent(heap);
    failed = false;
    try { heap.allocateInto(absent, nullptr, ErasedRef()); }
    catch (const std::invalid_argument&) { failed = true; }
    require(failed && !absent.get() && heap.liveCount() == 0, "invalid entry point published a callable");
  }
  for (const auto budget : {std::size_t(65536), std::size_t(0)}) {
    recursionAndCopies(budget);
    activeReplacement(budget);
    replacementDuringInvocation(budget);
    rootedParameter(budget);
    resultAndUnwind(budget);
  }
  std::cout << "CPP_MANAGED_CALLABLE:PASS\n";
}
