#include "Output.generated.hpp"
#include <limits>
#include <stdexcept>

using namespace hxhx::managed;

static unsigned effects = 0;
static void integerEffect(Heap& heap, ErasedRef, Root<Value>& output) {
  ++effects;
  heap.collect();
  std::fputs("effect:", stdout);
  output.set(Value::integer(23));
}

static void stringEffect(Heap& heap, ErasedRef, Root<Value>& output) {
  ++effects;
  heap.collect();
  std::fputs("text:", stdout);
  output.set(Value::string("value:"));
}

static void dynamicEffect(Heap& heap, ErasedRef, Root<Value>& output) {
  ++effects;
  heap.collect();
  std::fputs("dynamic:", stdout);
  output.set(Value::integer(29));
}

static void fail(Heap& heap, ErasedRef, Root<Value>&) {
  ++effects;
  heap.collect();
  throw std::runtime_error("argument failure");
}

int main() {
  Heap heap(0);
  {
    generatedOutputvalues(heap, true, std::numeric_limits<std::int32_t>::min(), Value::string(std::string("h\xc3\xa9\0z", 5)));
    generatedOutputvalues(heap, false, std::numeric_limits<std::int32_t>::max(), Value{});
    Root<Ref<CallablePayload<void(Root<Value>&)>>> integer(heap);
    heap.allocateInto(integer, &integerEffect, ErasedRef{});
    generatedOutputeffect(heap, Value::managed(integer.get()));
    Root<Ref<CallablePayload<void(Root<Value>&)>>> string(heap);
    heap.allocateInto(string, &stringEffect, ErasedRef{});
    generatedOutputtext(heap, Value::managed(string.get()));
    Root<Value> escaped(heap);
    generatedOutputdeferred(heap, escaped, 7);
    heap.collect();
    {
      ActiveCall<void()> selected(heap, escaped.get().asManaged().as<CallablePayload<void()>>());
      selected.invoke();
    }
    heap.allocateInto(integer, &fail, ErasedRef{});
    bool threw = false;
    try { generatedOutputeffect(heap, Value::managed(integer.get())); }
    catch (const std::runtime_error&) { threw = true; }
    if (!threw || effects != 3) throw std::runtime_error("output operand effects changed");
    std::fputs("after\n", stdout);
    generatedOutputerased(heap, Value{});
    generatedOutputerased(heap, Value::boolean(true));
    generatedOutputerased(heap, Value::boolean(false));
    generatedOutputerased(heap, Value::integer(std::numeric_limits<std::int32_t>::min()));
    generatedOutputerased(heap, Value::integer(std::numeric_limits<std::int32_t>::max()));
    generatedOutputerased(heap, Value::string(std::string("h\xc3\xa9\0z", 5)));
    heap.allocateInto(string, &dynamicEffect, ErasedRef{});
    generatedOutputerasedEffect(heap, Value::managed(string.get()));
    if (effects != 4) throw std::runtime_error("erased output operand ran more than once");
    bool unsupported = false;
    try { generatedOutputerased(heap, Value::managed(string.get())); }
    catch (const std::logic_error&) { unsupported = true; }
    if (!unsupported) throw std::runtime_error("erased output accepted an unsupported callable tag");
  }
  heap.collect();
  if (heap.liveCount() != 0) throw std::runtime_error("output retained managed storage");
  // A valid read-only stream makes native writing fail without using a closed FILE.
  if (std::fflush(stdout) != 0 || std::freopen("/dev/null", "r", stdout) == nullptr)
    throw std::runtime_error("cannot prepare output failure observer");
  bool writeFailed = false;
  try { generatedOutputvalues(heap, false, 0, Value::string("unwritten")); }
  catch (const std::runtime_error&) { writeFailed = true; }
  if (!writeFailed) throw std::runtime_error("output ignored a native write failure");
}
