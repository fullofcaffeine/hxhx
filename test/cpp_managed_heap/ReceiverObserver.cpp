#include "Generated.hpp"
#include <iostream>
#include <stdexcept>

// Opaque payloads test transport and lifetime, not Haxe class representation.
struct ReceiverProbe { int id; explicit ReceiverProbe(int value) : id(value) {} };
namespace hxhx::managed {
template<> struct Trace<::ReceiverProbe> {
  static void visit(const ::ReceiverProbe&, Visitor&) noexcept {}
};
}

int main() {
  using namespace hxhx::managed;
  Heap heap(0);
  {
    Root<Ref<ReceiverProbe>> first(heap), second(heap);
    heap.allocateInto(first, 17);
    heap.allocateInto(second, 29);
    const auto identity = ErasedRef(first.get());
    const auto a = Value::managed(identity);
    const auto b = Value::managed(ErasedRef(second.get()));
    Root<Value> result(heap), captured(heap), forwarded(heap), child(heap);
    // No allocation occurs between dropping the caller root and entry. The
    // method's own ingress must protect the receiver before parameter cells.
    first.set({});
    generated_self(heap, a, result, b);
    std::cout << (result.get().asManaged() == identity ? "true\n" : "false\n");
    second.set({});
    generated_capture(heap, a, captured, b);
    generated_forward(heap, a, forwarded);
    if (b.asManaged().as<ReceiverProbe>()->id != 29)
      throw std::runtime_error("escaping closure lost its captured argument");
    generated_direct(heap, b, result);
    const bool distinct = !(result.get().asManaged() == identity);
    const auto ignored = generated_ignore(heap, a, 4);
    first.set({});
    second.set({});
    result.set({});
    heap.collect();
    {
      ActiveCall<void(Root<Value>&)> call(heap, captured.get().asManaged().as<CallablePayload<void(Root<Value>&)>>());
      call.invoke(result);
    }
    std::cout << (result.get().asManaged() == identity ? "true\n" : "false\n");
    if (identity.as<ReceiverProbe>()->id != 17)
      throw std::runtime_error("captured receiver was not traced");
    {
      ActiveCall<void(Root<Value>&)> call(heap, forwarded.get().asManaged().as<CallablePayload<void(Root<Value>&)>>());
      call.invoke(child);
    }
    captured.set({});
    forwarded.set({});
    result.set({});
    heap.collect();
    {
      ActiveCall<void(Root<Value>&)> call(heap, child.get().asManaged().as<CallablePayload<void(Root<Value>&)>>());
      call.invoke(result);
    }
    std::cout << (result.get().asManaged() == identity ? "true\n" : "false\n");
    std::cout << (distinct ? "true\n" : "false\n") << ignored << '\n';
  }
  heap.collect();
  if (heap.rootCount() != 0 || heap.liveCount() != 0)
    throw std::runtime_error("receiver transport leaked roots or captured values");
}
