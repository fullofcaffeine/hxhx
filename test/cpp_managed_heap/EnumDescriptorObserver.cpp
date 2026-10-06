#include "EnumDescriptors.hpp"
#include <iostream>
#include <stdexcept>
#include <string>

using namespace hxhx::managed;
static void require(bool condition) {
  if (!condition) throw std::runtime_error("generated enum descriptor changed its source contract");
}

int main() {
  require(std::string(choice.identity) == "Main.Choice");
  require(std::string(other.identity) == "Main.Other");
  require(choice.constructorCount == 2 && other.constructorCount == 1);
  require(std::string(choice.constructors[0].name) == "Empty" && choice.constructors[0].arity == 0);
  require(std::string(choice.constructors[1].name) == "Carry" && choice.constructors[1].arity == 1);
  require(std::string(other.constructors[0].name) == "Empty");
  Heap heap(0);
  Root<Ref<EnumPayload>> value(heap);
  heap.allocateInto(value, choice, 1, std::vector<Value>{Value::integer(7)});
  heap.collect();
  require(&value.get()->descriptor() == &choice && value.get()->constructorIndex() == 1);
  require(value.get()->constructorIndex(choice) == 1);
  bool rejected = false;
  try { value.get()->constructorIndex(other); }
  catch (const std::invalid_argument&) { rejected = true; }
  require(rejected);
  const auto copiedDescriptor = choice;
  rejected = false;
  try { value.get()->constructorIndex(copiedDescriptor); }
  catch (const std::invalid_argument&) { rejected = true; }
  require(rejected); // Equal descriptor contents do not grant declaration identity.
  require(value.get()->read(0).asInteger() == 7);
  value.set({});
  heap.collect();
  require(heap.liveCount() == 0);
  std::cout << "CPP_MANAGED_ENUM_DESCRIPTORS:PASS\n";
}
