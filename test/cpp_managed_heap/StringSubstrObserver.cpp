#define main generated_main
#include HXHX_LOCAL_PROGRAM
#undef main
#include "SubstrBoundary.hpp"
#include <stdexcept>
#include <string>

using namespace hxhx::managed;
static std::string events;
static int mode = 0;

// Collection in later arguments checks that every callable and its result stay
// rooted. Failures must stop subsequent callbacks and preserve the destination.
static void receiver(Heap& heap, ErasedRef, Root<Value>& result) {
  events += 'r';
  heap.collect();
  if (mode == 1) throw std::runtime_error("receiver");
  result.set(mode == 4 ? Value{} : Value::string("abcdef"));
}
static void position(Heap& heap, ErasedRef, Root<Value>& result) {
  events += 'p';
  heap.collect();
  if (mode == 2) throw std::runtime_error("position");
  result.set(Value::integer(1));
}
static void length(Heap& heap, ErasedRef, Root<Value>& result) {
  events += 'l';
  heap.collect();
  if (mode == 3) throw std::runtime_error("length");
  result.set(mode == 5 ? Value{} : Value::integer(2));
}

// Expectations are literal black-box observations, independent of the runtime
// normalization algorithm. Keep both whole emoji and split surrogate cases.
static void runtimeCases() {
  struct Case { const char* text; int start; int length; const char* expected; };
  const Case cases[] = {
    {"abcdef", 0, -2, "abcd"}, {"abcdef", 1, -2, "bcde"},
    {"abcdef", 2, -2, ""}, {"abcdef", 3, -5, "d"},
    {"abcdef", -10, 2, "ab"}, {"abcdef", -2, 20, "ef"},
    {"abcdef", INT32_MIN, 2, "ab"}, {"abcdef", INT32_MAX, INT32_MAX, ""},
    {"abcdef", 2, INT32_MIN, ""}, {"abcdef", 2, INT32_MAX, "cdef"},
    {"", 0, 1, ""}, {"abcdef", 2, 0, ""},
    {"Aé😀Z", 1, 1, "é"}, {"Aé😀Z", 2, 2, "😀"},
    {"Aé😀Z", 2, 1, "�"}, {"Aé😀Z", 3, 1, "�"},
    {"Aé😀Z", 3, 2, "�Z"}, {"Aé😀Z", 0, 3, "Aé�"},
    {"Aé😀Z", -1, 1, "Z"}, {"Aé😀Z", -2, -2, ""}
  };
  for (const auto& item : cases) {
    const auto result = stringSubstr(Value::string(item.text), Value::integer(item.start), Value::integer(item.length));
    if (result.asString() != item.expected) throw std::runtime_error("native substring bounds differ");
  }
  if (stringSubstr(Value::string("abcdef"), Value::integer(2), Value{}).asString() != "cdef" ||
      stringSubstr(Value::string("abcdef"), Value{}, Value::integer(2)).asString() != "ab" ||
      stringSubstr(Value{}, Value::integer(1), Value::integer(2)).asString() != "")
    throw std::runtime_error("native substring null behavior differs");
  if (stringSubstr(Value::string(std::string("a\0bc", 4)), Value::integer(1), Value::integer(2)).asString() != std::string("\0b", 2))
    throw std::runtime_error("substring truncated an embedded zero");
}

int main() {
  runtimeCases();
  Heap heap(0);
  hxhx_program_run(heap);
  {
    Root<Ref<CallablePayload<void(Root<Value>&)>>> text(heap), start(heap), count(heap);
    heap.allocateInto(text, &receiver, ErasedRef{});
    heap.allocateInto(start, &position, ErasedRef{});
    heap.allocateInto(count, &length, ErasedRef{});
    for (mode = 0; mode != 6; ++mode) {
      events.clear();
      std::string error;
      {
        Root<Value> result(heap, Value::string("unchanged"));
        try {
          observeStringSubstr(heap, result, Value::managed(text.get()), Value::managed(start.get()), Value::managed(count.get()));
          const std::string expected = mode == 4 ? "" : mode == 5 ? "bcdef" : "bc";
          if (result.get().asString() != expected) throw std::runtime_error("unexpected substring result");
        } catch (const std::exception& failure) {
          error = failure.what();
          if (result.get().asString() != "unchanged") throw std::runtime_error("substring published before completion");
        }
      }
      const std::string expectedError = mode == 1 ? "receiver" : mode == 2 ? "position" : mode == 3 ? "length" : "";
      const std::string expectedEvents = mode == 1 ? "r" : mode == 2 ? "rp" : "rpl";
      if (error != expectedError || events != expectedEvents || heap.rootCount() != 3)
        throw std::runtime_error("substring changed operand effects or root lifetime");
      heap.collect();
      if (heap.liveCount() != 4) throw std::runtime_error("substring retained temporary storage");
    }
  }
  heap.collect();
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 1)
    throw std::runtime_error("substring retained temporary roots");
}
