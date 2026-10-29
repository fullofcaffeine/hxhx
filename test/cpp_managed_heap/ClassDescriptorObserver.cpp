#include "Generated.hpp"
#include <stdexcept>
#include <string>
using namespace hxhx::managed;

// Compare the authored class handle with the descriptor used by real instance storage.
int main() {
  Heap heap(0);
  Root<Value> value(heap);
  pickDescriptor(heap, value);
  if (value.get().kind() != ValueKind::Descriptor)
    throw std::runtime_error("class value is not descriptor storage");
  const auto* descriptor = value.get().asDescriptor();
  if (std::string(descriptor->identity) != "Main.Key" || !descriptor->hasInstanceLayout)
    throw std::runtime_error("class value lost its declaration identity");
  Root<Ref<InstancePayload>> instance(heap);
  const InstanceDescriptor application{*descriptor};
  heap.allocateInto(instance, application, std::vector<Value>{Value::integer(7)});
  Root<Value> alias(heap, value.get());
  value.set({});
  heap.collect();
  if (alias.get().asDescriptor() != &instance.get()->descriptor() || heap.liveCount() != 1
      || instance.get()->read(*alias.get().asDescriptor(), 0).asInteger() != 7)
    throw std::runtime_error("class handle and instance descriptor diverged");
  if (!compare_same(heap, alias.get(), alias.get()) || compare_different(heap, alias.get(), alias.get())
      || !compare_same(heap, Value{}, Value{}) || compare_same(heap, Value{}, alias.get())
      || compare_same(heap, alias.get(), Value{}) || !compare_different(heap, Value{}, alias.get())
      || !compare_different(heap, alias.get(), Value{}))
    throw std::runtime_error("class equality lost null or copied descriptor identity");
  // Exercise the representation boundary with equal text and a distinct address.
  // This is a low-level control, not an authored Class<Key> conversion claim.
  const ClassDescriptor distinct{descriptor->identity, false, 0, nullptr};
  if (compare_same(heap, alias.get(), Value::descriptor(&distinct))
      || !compare_different(heap, alias.get(), Value::descriptor(&distinct)))
    throw std::runtime_error("class equality compared descriptor text instead of identity");
  bool rejected = false;
  try { compare_same(heap, alias.get(), Value::integer(7)); }
  catch (const std::bad_variant_access&) { rejected = true; }
  if (!rejected || heap.rootCount() != 3)
    throw std::runtime_error("invalid descriptor storage passed or leaked roots");
}
