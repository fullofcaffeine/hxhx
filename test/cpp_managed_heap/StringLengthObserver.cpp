#include HXHX_LOCAL_PROGRAM
#include <stdexcept>
#include <string>

using namespace hxhx::managed;
static int calls = 0;
static bool fail = false;

// Collection and failure inside the receiver must preserve the caller's roots and result.
static void receiver(Heap& heap, ErasedRef, Root<Value>& result) {
  ++calls;
  heap.collect();
  if (fail) throw std::runtime_error("receiver");
  result.set(Value::string("😀!"));
}

int main() {
  Heap heap(0);
  {
    Root<Value> result(heap);
    struct Case { std::string value; int expected; };
    const Case cases[] = {
      {"", 0}, {"abc", 3}, {"é", 1}, {"😀", 2},
      {"é", 2}, {"Aé😀Z", 5}, {std::string("a\0b", 3), 3}
    };
    for (const auto& item : cases) {
      result.set(Value::integer(generated_read(heap, Value::string(item.value))));
      if (result.get().asInteger() != item.expected) throw std::runtime_error("String length differs");
    }
    result.set(Value::integer(generated_read(heap, Value{})));
    if (result.get().asInteger() != 0) throw std::runtime_error("null String length differs");
    Root<Ref<CallablePayload<void(Root<Value>&)>>> callback(heap);
    heap.allocateInto(callback, &receiver, ErasedRef{});
    result.set(Value::integer(generated_boundary(heap, Value::managed(callback.get()))));
    if (calls != 1 || result.get().asInteger() != 3) throw std::runtime_error("String receiver effects differ");
    fail = true;
    result.set(Value::integer(99));
    std::string error;
    try { result.set(Value::integer(generated_boundary(heap, Value::managed(callback.get())))); }
    catch (const std::runtime_error& failure) { error = failure.what(); }
    if (error != "receiver" || calls != 2 || result.get().asInteger() != 99 || heap.rootCount() != 2)
      throw std::runtime_error("String length changed failure or root cleanup");
  }
  heap.collect();
  if (heap.rootCount() != 0 || heap.liveCount() != 0 || heap.staticRootCount() != 0)
    throw std::runtime_error("String length retained temporary storage");
}
