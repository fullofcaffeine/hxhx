// Inspect generated output without changing it. The Haxe fixture owns effects.
#define main hxhx_fixture_main
#include "Main.cpp"
#undef main

int observe() {
  using namespace hxhx::managed;
  Heap heap(0);
#if EXPECT_THROW
  bool caught = false;
  try { hxhx_program_run(heap); }
  catch (const ThrownValue& error) {
    if (error.value().asString() != "enum stop") return 10;
    caught = true;
  }
  if (!caught) return 18;
#else
  hxhx_program_run(heap);
#endif
  heap.collect();
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 6) return 11;
  const auto storage = heap.requireStatic<hxhx_statics_program>();
  const auto omitted = storage->field_0.read().asManaged().as<EnumPayload>();
  const auto pair = storage->field_2.read().asManaged().as<EnumPayload>();
  const auto text = storage->field_3.read().asManaged().as<EnumPayload>();
  if (storage->field_1.read().asInteger() != (EXPECT_THROW ? 123 : 12)) return 12;
  if (std::string(pair->descriptor().identity) != "Main.Tree" || pair->constructorIndex() != 1 || pair->size() != 2) return 13;
  if (&omitted->descriptor() != &pair->descriptor() || omitted->constructorIndex() != 2 || omitted->size() != 1 || omitted->read(0).kind() != ValueKind::Null) return 14;
  for (std::size_t index = 0; index < 2; ++index) {
    const auto leaf = pair->read(index).asManaged().as<EnumPayload>();
    if (&leaf->descriptor() != &pair->descriptor() || leaf->constructorIndex() != 0 || leaf->size() != 1 || leaf->read(0).asInteger() != static_cast<int>(index + 1)) return 15;
  }
  if (&text->descriptor() != &pair->descriptor() || text->constructorIndex() != 0 || text->read(0).asString() != "kept") return 16;
  storage->field_0.write({});
  storage->field_2.write({});
  storage->field_3.write({});
  heap.collect();
  if (heap.liveCount() != 1 || heap.rootCount() != 0) return 17;
  return 0;
}
int main() {
  const int first = observe();
  return first != 0 ? first : observe();
}
