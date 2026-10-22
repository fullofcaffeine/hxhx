#define main generated_main
#include HXHX_LOCAL_PROGRAM
#undef main
#include "IndexOfBoundary.hpp"
#include <stdexcept>
#include <string>

using namespace hxhx::managed;
static std::string events;
static int mode = 0;

// Later operands collect to expose missing roots. Each failure must stop the
// next operand and leave the caller's destination unchanged.
static void receiver(Heap& heap, ErasedRef, Root<Value>& result) {
  events += 'r';
  heap.collect();
  if (mode == 1) throw std::runtime_error("receiver");
  result.set(mode == 4 ? Value{} : Value::string("abcabc"));
}
static void needle(Heap& heap, ErasedRef, Root<Value>& result) {
  events += 'n';
  heap.collect();
  if (mode == 2) throw std::runtime_error("needle");
  result.set(mode == 6 ? Value{} : Value::string("bc"));
}
static void start(Heap& heap, ErasedRef, Root<Value>& result) {
  events += 's';
  heap.collect();
  if (mode == 3) throw std::runtime_error("start");
  result.set(mode == 5 ? Value{} : Value::integer(2));
}

// Literal expectations come from IndexOfReference.hx under Haxe 4.3.7/hxcpp.
// They do not share the runtime's byte decoding or search algorithm.
static void runtimeCases() {
  struct Case { const char* text; const char* needle; int start; int expected; };
  const Case cases[] = {
    {"abcabc", "bc", 0, 1}, {"abcabc", "bc", 2, 4}, {"aaaa", "aa", 1, 1},
    {"abc", "", 2, 2}, {"abc", "", 3, 3}, {"abc", "", 4, 3},
    {"abc", "", INT32_MAX, 3}, {"abc", "z", 0, -1}, {"abc", "a", INT32_MAX, -1},
    {"", "", 0, 0}, {"", "", 1, 0}, {"abc", "a", -1, 0},
    {"Aé😀Z😀", "é", 0, 1}, {"Aé😀Z😀", "😀", 0, 2}, {"Aé😀Z😀", "Z", 0, 4},
    {"Aé😀Z😀", "😀", 3, 5}, {"Aé😀Z😀", "", 3, 3}, {"Aé😀Z😀", "😀Z", 0, 2}
  };
  for (const auto& item : cases)
    if (stringIndexOf(Value::string(item.text), Value::string(item.needle), Value::integer(item.start)).asInteger() != item.expected)
      throw std::runtime_error("native search position differs");
  if (stringIndexOf(Value{}, Value::string("a"), Value{}).asInteger() != -1 ||
      stringIndexOf(Value{}, Value::string(""), Value{}).asInteger() != -1 ||
      stringIndexOf(Value{}, Value{}, Value{}).asInteger() != -1 ||
      stringIndexOf(Value::string("abc"), Value{}, Value{}).asInteger() != 0 ||
      stringIndexOf(Value::string("abc"), Value{}, Value::integer(2)).asInteger() != 2 ||
      stringIndexOf(Value::string("abc"), Value{}, Value::integer(99)).asInteger() != 3 ||
      stringIndexOf(Value::string("abc"), Value::string("b"), Value{}).asInteger() != 1)
    throw std::runtime_error("native null search behavior differs");
  const auto zeroes = Value::string(std::string("a\0bc\0", 5));
  if (stringIndexOf(zeroes, Value::string(std::string("\0", 1)), Value::integer(2)).asInteger() != 4 ||
      stringIndexOf(zeroes, Value::string(std::string("bc\0", 3)), Value{}).asInteger() != 2)
    throw std::runtime_error("search truncated an embedded zero");
  // Safety policy for an unspecified bound: upstream crashes for INT_MIN.
  if (stringIndexOf(Value::string("abc"), Value::string("a"), Value::integer(INT32_MIN)).asInteger() != 0)
    throw std::runtime_error("negative search start was not safely clamped");
}

int main() {
  runtimeCases();
  Heap heap(0);
  hxhx_program_run(heap);
  {
    Root<Ref<CallablePayload<void(Root<Value>&)>>> text(heap), search(heap), position(heap);
    heap.allocateInto(text, &receiver, ErasedRef{});
    heap.allocateInto(search, &needle, ErasedRef{});
    heap.allocateInto(position, &start, ErasedRef{});
    for (mode = 0; mode != 7; ++mode) {
      events.clear();
      std::string error;
      {
        Root<Value> result(heap, Value::integer(999));
        try {
          result.set(Value::integer(observeStringIndexOf(heap, Value::managed(text.get()), Value::managed(search.get()), Value::managed(position.get()))));
          const int expected = mode == 4 ? -1 : mode == 5 ? 1 : mode == 6 ? 2 : 4;
          if (result.get().asInteger() != expected) throw std::runtime_error("unexpected search result");
        } catch (const std::exception& failure) {
          error = failure.what();
          if (result.get().asInteger() != 999) throw std::runtime_error("search published before completion");
        }
      }
      const std::string expectedError = mode == 1 ? "receiver" : mode == 2 ? "needle" : mode == 3 ? "start" : "";
      const std::string expectedEvents = mode == 1 ? "r" : mode == 2 ? "rn" : "rns";
      if (error != expectedError || events != expectedEvents || heap.rootCount() != 3)
        throw std::runtime_error("search changed operand effects or root lifetime");
      heap.collect();
      if (heap.liveCount() != 4) throw std::runtime_error("search retained temporary storage");
    }
  }
  heap.collect();
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 1)
    throw std::runtime_error("search retained temporary roots");
}
