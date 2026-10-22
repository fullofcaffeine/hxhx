#include "ManagedValue.hpp"
#include <iostream>
#include <stdexcept>

using namespace hxhx::managed;

// Separate physical layouts represent separately generated program storage.
// The runtime must not infer any Haxe class, field, or initializer ordering.
struct ProgramStorage {
  Value slot;
  int* destroyed;
  explicit ProgramStorage(int& destroyed) : destroyed(&destroyed) {}
  ~ProgramStorage() noexcept { ++*destroyed; }
};

struct OtherStorage {
  Value slot;
};

struct FailedStorage {
  explicit FailedStorage(bool fail) {
    if (fail) throw std::runtime_error("construction failure");
  }
};

namespace hxhx::managed {
template<> struct Trace<ProgramStorage> {
  static void visit(const ProgramStorage& value, Visitor& visitor) noexcept {
    Trace<Value>::visit(value.slot, visitor);
  }
};
template<> struct Trace<OtherStorage> {
  static void visit(const OtherStorage& value, Visitor& visitor) noexcept {
    Trace<Value>::visit(value.slot, visitor);
  }
};
template<> struct Trace<FailedStorage> {
  static void visit(const FailedStorage&, Visitor&) noexcept {}
};
}

static void require(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}

static void lifetime(std::size_t budget) {
  int destroyed = 0;
  {
    Heap heap(budget);
    bool missing = false;
    try { static_cast<void>(heap.requireStatic<ProgramStorage>()); }
    catch (const std::logic_error&) { missing = true; }
    require(missing, "unpublished storage must not silently initialize itself");
    {
      Root<Ref<ProgramStorage>> storage(heap);
      heap.allocateStaticInto(storage, destroyed);
      Root<Ref<ArrayPayload>> array(heap);
      heap.allocateInto(array, ArrayRepresentation::Reference);
      // A static -> array -> static cycle exercises ordinary edge tracing.
      array.get()->append(Value::managed(ErasedRef(storage.get())));
      storage.get()->slot = Value::managed(ErasedRef(array.get()));
    }
    require(heap.rootCount() == 0 && heap.staticRootCount() == 1, "static retention borrowed a stack root");
    heap.collect();
    const auto selected = heap.requireStatic<ProgramStorage>();
    require(heap.liveCount() == 2 && destroyed == 0, "static graph died after publication roots left");
    require(selected->slot.asManaged().as<ArrayPayload>()->read(0).asManaged().as<ProgramStorage>() == selected,
            "static cycle changed identity");
    {
      Root<Ref<ProgramStorage>> duplicate(heap);
      bool rejected = false;
      try { heap.allocateStaticInto(duplicate, destroyed); }
      catch (const std::logic_error&) { rejected = true; }
      require(rejected && !duplicate.get() && heap.requireStatic<ProgramStorage>() == selected,
              "duplicate publication replaced live static storage");
      require(heap.liveCount() == 2 && heap.staticRootCount() == 1, "duplicate publication allocated storage");
    }
    selected->slot = Value{};
    heap.collect();
    require(heap.liveCount() == 1, "overwriting a static field retained its old cycle");
    {
      Root<Ref<OtherStorage>> other(heap);
      heap.allocateStaticInto(other);
      other.get()->slot = Value::integer(std::int32_t(47));
    }
    heap.collect();
    require(heap.staticRootCount() == 2 && heap.requireStatic<OtherStorage>()->slot.asInteger() == 47,
            "distinct static layouts alias each other");
  }
  require(destroyed == 1, "heap shutdown did not destroy static storage exactly once");
}

static void failureAndIsolation() {
  int firstDestroyed = 0;
  int secondDestroyed = 0;
  {
    Heap first(0), second(0);
    Root<Ref<ProgramStorage>> firstRoot(first), secondRoot(second);
    bool rejected = false;
    try { first.allocateStaticInto(secondRoot, firstDestroyed); }
    catch (const std::invalid_argument&) { rejected = true; }
    require(rejected && !secondRoot.get() && first.staticRootCount() == 0 && second.staticRootCount() == 0,
            "wrong-heap destination published static storage");
    first.allocateStaticInto(firstRoot, firstDestroyed);
    second.allocateStaticInto(secondRoot, secondDestroyed);
    firstRoot.get()->slot = Value::integer(std::int32_t(11));
    secondRoot.get()->slot = Value::integer(std::int32_t(29));
    firstRoot.set({});
    secondRoot.set({});
    first.collect();
    second.collect();
    require(first.requireStatic<ProgramStorage>()->slot.asInteger() == 11
              && second.requireStatic<ProgramStorage>()->slot.asInteger() == 29,
            "heaps share process-global static values");
    Root<Ref<FailedStorage>> failed(first);
    bool constructionFailed = false;
    try { first.allocateStaticInto(failed, true); }
    catch (const std::runtime_error&) { constructionFailed = true; }
    require(constructionFailed && !failed.get() && first.staticRootCount() == 1,
            "failed native construction published static storage");
    // Native allocation failure is not a source initializer retry policy.
    first.allocateStaticInto(failed, false);
    require(static_cast<bool>(first.requireStatic<FailedStorage>()), "failed allocation left a phantom registration");
  }
  require(firstDestroyed == 1 && secondDestroyed == 1, "isolated heap teardown lost a static owner");
}

int main() {
  lifetime(65536);
  lifetime(0);
  failureAndIsolation();
  std::cout << "CPP_MANAGED_STATIC_ROOT:PASS\n";
}
