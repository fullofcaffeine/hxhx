#include "ManagedValue.hpp"
#include <cstdlib>
#include <iostream>
#include <new>
#include <stdexcept>

// Test-side allocation failure, without a production allocator switch. The
// replacement still uses malloc/free so sanitizer memory tracking remains active.
static int allocationsBeforeFailure = -1;
void* operator new(std::size_t size) {
  if (allocationsBeforeFailure == 0) {
    allocationsBeforeFailure = -1;
    throw std::bad_alloc();
  }
  if (allocationsBeforeFailure > 0) --allocationsBeforeFailure;
  if (void* value = std::malloc(size == 0 ? 1 : size)) return value;
  throw std::bad_alloc();
}
void operator delete(void* value) noexcept { std::free(value); }
void operator delete(void* value, std::size_t) noexcept { std::free(value); }

using namespace hxhx::managed;

static void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

int main() {
  Heap heap(0);
  Root<Ref<Value>> slot(heap);
  heap.allocateInto(slot, Value::integer(42));
  const auto identity = slot.get().allocationId();
  allocationsBeforeFailure = 0;
  bool failed = false;
  try { heap.allocateInto(slot, Value::integer(99)); }
  catch (const std::bad_alloc&) { failed = true; }
  require(failed && allocationsBeforeFailure == -1 && slot.get().allocationId() == identity && slot.get()->asInteger() == 42,
          "allocation failure replaced the published value");
  require(heap.liveCount() == 1, "allocation failure leaked a node");

  Root<Ref<ArrayPayload>> array(heap);
  heap.allocateInto(array, ArrayRepresentation::Integer);
  array.get()->append(Value::integer(7));
  *slot.get().operator->() = Value::managed(array.get());
  array.set({});
  const auto originalArray = slot.get()->asManaged().allocationId();
  const auto longString = Value::string(std::string(4096, 'x'));
  allocationsBeforeFailure = 0;
  failed = false;
  try { *slot.get().operator->() = longString; }
  catch (const std::bad_alloc&) { failed = true; }
  heap.collect();
  require(failed && allocationsBeforeFailure == -1 && slot.get()->asManaged().allocationId() == originalArray,
          "failed value replacement lost the old managed edge");
  require(slot.get()->asManaged().as<ArrayPayload>()->read(0).asInteger() == 7 && heap.liveCount() == 2,
          "collection after failed replacement lost reachable storage");
  slot.set({});
  heap.collect();
  require(heap.liveCount() == 0 && heap.allocationBytes() == 0, "failure recovery left live nodes");
  // Fail each allocation in first static publication: registry storage, then
  // the payload node. Neither failure may replace an existing destination.
  for (int failAt = 0; failAt < 2; ++failAt) {
    Heap owner(0);
    Root<Ref<Value>> destination(owner);
    owner.allocateInto(destination, Value::integer(7));
    const auto prior = destination.get().allocationId();
    allocationsBeforeFailure = failAt;
    bool publicationFailed = false;
    try { owner.allocateStaticInto(destination, Value::integer(9)); }
    catch (const std::bad_alloc&) { publicationFailed = true; }
    owner.collect();
    require(publicationFailed && allocationsBeforeFailure == -1
              && destination.get().allocationId() == prior && destination.get()->asInteger() == 7,
            "failed static publication changed its destination");
    require(owner.staticRootCount() == 0 && owner.liveCount() == 1,
            "failed static publication left a registered or leaked node");
    owner.allocateStaticInto(destination, Value::integer(11));
    destination.set({});
    owner.collect();
    require(owner.requireStatic<Value>()->asInteger() == 11 && owner.liveCount() == 1,
            "static allocation retry lost its graph or retained the prior destination");
  }
  std::cout << "CPP_MANAGED_ALLOCATION_FAILURE:PASS\n";
}
