package backend.cpp;

/**
	Small target-owned C++ runtime support fragments used by `CppTargetCore`.

	Why
	- C++ Full1 burn-down needs a few runtime/library surfaces while the backend is
	  still source-only.
	- Keeping these fragments here avoids turning the main emitter into a dumping
	  ground for target runtime code.

	What/How
	- Each method returns one cohesive support block.
	- `CppTargetCore` decides where each block belongs in the generated file so
	  declaration order remains explicit at the call site.
**/
class CppRuntimeSupport {
	public static function enumValueTypeLines():Array<String> {
		return [
			"struct EnumValue {",
			"  std::string tag;",
			"  int index;",
			"  std::vector<std::string> parameters;",
			"  explicit EnumValue(std::string tag = std::string(), int index = 0, std::vector<std::string> parameters = {}) : tag(tag), index(index), parameters(parameters) {}",
			"  std::string getName() const { return tag; }",
			"  int getIndex() const { return index; }",
			"  std::vector<std::string> getParameters() const { return parameters; }",
			"};"
		];
	}

	public static function anyIsTypeLines():Array<String> {
		return [
			"static bool __hxhx_is_type(const std::any& value, const std::string& type) {",
			"  if (type == \"Dynamic\" || type == \"Any\") return true;",
			"  if (!value.has_value()) return type == \"Null\";",
			"  const std::type_info& valueType = value.type();",
			"  if (type == \"Array\") return valueType == typeid(std::vector<std::string>) || valueType == typeid(std::vector<int>);",
			"  if (type == \"String\" || type == \"StdTypes.String\") return valueType == typeid(std::string) || valueType == typeid(const char*);",
			"  if (type == \"Bool\" || type == \"StdTypes.Bool\") return valueType == typeid(bool);",
			"  if (type == \"Int\" || type == \"StdTypes.Int\") return valueType == typeid(int);",
			"  if (type == \"Float\" || type == \"StdTypes.Float\") return valueType == typeid(double) || valueType == typeid(float);",
			"  return false;",
			"}"
		];
	}

	public static function enumValueDynamicLines():Array<String> {
		return [
			"static bool __hxhx_is_enum_value(const std::shared_ptr<EnumValue>& value) {",
			"  return value != nullptr;",
			"}",
			"",
			"static bool __hxhx_is_enum_value(const std::any& value) {",
			"  return value.has_value() && value.type() == typeid(std::shared_ptr<EnumValue>) && std::any_cast<std::shared_ptr<EnumValue>>(value) != nullptr;",
			"}",
			"",
			"template<typename T>",
			"static bool __hxhx_is_enum_value(const T&) {",
			"  return false;",
			"}",
			"",
			"static std::shared_ptr<EnumValue> __hxhx_enum_value_ptr(const std::any& value) {",
			"  if (__hxhx_is_enum_value(value)) return std::any_cast<std::shared_ptr<EnumValue>>(value);",
			"  return nullptr;",
			"}",
			"",
			"static std::vector<std::string> __hxhx_string_vector_any(const std::any& value) {",
			"  if (!value.has_value()) return {};",
			"  if (value.type() == typeid(std::vector<std::string>)) return std::any_cast<std::vector<std::string>>(value);",
			"  return {};",
			"}"
		];
	}

	public static function compareLines():Array<String> {
		return [
			"template<typename L, typename R>",
			"static int __hxhx_compare(const L& left, const R& right) {",
			"  return __hxhx_stringify(left).compare(__hxhx_stringify(right));",
			"}",
			"",
			"template<typename T>",
			"static int __hxhx_compare(const T& left, const T& right) {",
			"  if constexpr (std::is_arithmetic_v<T>) return left < right ? -1 : (left > right ? 1 : 0);",
			"  else return left < right ? -1 : (left > right ? 1 : 0);",
			"}",
			"",
			"static int __hxhx_compare(const std::shared_ptr<EnumValue>& left, const std::shared_ptr<EnumValue>& right) {",
			"  if (left == nullptr && right == nullptr) return 0;",
			"  if (left == nullptr) return -1;",
			"  if (right == nullptr) return 1;",
			"  int indexDiff = left->getIndex() - right->getIndex();",
			"  if (indexDiff != 0) return indexDiff < 0 ? -1 : 1;",
			"  return left->getName().compare(right->getName());",
			"}",
			"",
			"static int __hxhx_compare(const std::any& left, const std::any& right) {",
			"  if (__hxhx_is_enum_value(left) && __hxhx_is_enum_value(right)) return __hxhx_compare(__hxhx_enum_value_ptr(left), __hxhx_enum_value_ptr(right));",
			"  if (left.has_value() && right.has_value() && left.type() == typeid(std::string) && right.type() == typeid(std::string)) return __hxhx_compare(std::any_cast<std::string>(left), std::any_cast<std::string>(right));",
			"  if (left.has_value() && right.has_value() && left.type() == typeid(int) && right.type() == typeid(int)) return __hxhx_compare(std::any_cast<int>(left), std::any_cast<int>(right));",
			"  if (left.has_value() && right.has_value() && left.type() == typeid(double) && right.type() == typeid(double)) return __hxhx_compare(std::any_cast<double>(left), std::any_cast<double>(right));",
			"  return __hxhx_stringify(left).compare(__hxhx_stringify(right));",
			"}"
		];
	}
}
