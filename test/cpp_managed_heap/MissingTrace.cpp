#include "ManagedHeap.hpp"

// Deliberately absent Trace specialization: unknown payloads must be rejected.
struct UnknownPayload {};

int main() {
  hxhx::managed::Heap heap;
  hxhx::managed::Root<hxhx::managed::Ref<UnknownPayload>> value(heap);
  heap.allocateInto(value);
}
