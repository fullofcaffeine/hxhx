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
	public static function borrowedSharedPtrLines():Array<String> {
		return [
			"template<typename T>",
			"static std::shared_ptr<T> __hxhx_borrowed_shared(T* value) {",
			"  return std::shared_ptr<T>(value, [](T*) {});",
			"}"
		];
	}

	public static function borrowedSharedPtrExpr(typeName:String, valueExpr:String):String {
		return "__hxhx_borrowed_shared<" + typeName + ">(" + valueExpr + ")";
	}

	public static function missingDeclarationLines(cleanName:String):Null<Array<String>> {
		return switch (cleanName) {
			case "KeyValueIterator":
				["struct KeyValueIterator {", "  virtual ~KeyValueIterator() = default;", "};"];
			case "IMap":
				[
					"template<typename K, typename V>",
					"struct IMap {",
					"  virtual ~IMap() = default;",
					"  virtual std::optional<V> get(K k) = 0;",
					"  virtual void set(K k, V v) = 0;",
					"  virtual bool exists(K k) = 0;",
					"  virtual bool remove(K k) = 0;",
					"  virtual std::shared_ptr<__hxhx_iterator<K>> keys() = 0;",
					"  virtual std::shared_ptr<__hxhx_iterator<V>> iterator() = 0;",
					"  virtual std::shared_ptr<KeyValueIterator> keyValueIterator() = 0;",
					"  virtual std::shared_ptr<IMap<K, V>> copy() = 0;",
					"  virtual std::string toString() = 0;",
					"  virtual void clear() = 0;",
					"};"
				];
			case "StringMap":
				[
					"struct __hxhx_stringmap_key_iterator : public __hxhx_iterator<std::string> {",
					"  std::vector<std::string> values;",
					"  std::size_t index;",
					"  explicit __hxhx_stringmap_key_iterator(std::vector<std::string> values) : values(std::move(values)), index(0) {}",
					"  bool hasNext() override { return index < values.size(); }",
					"  std::string next() override { return values[index++]; }",
					"};",
					"template<typename V>",
					"struct StringMap {",
					"  std::map<std::string, V> __values;",
					"  V get(std::string key) {",
					"    auto it = __values.find(key);",
					"    return it == __values.end() ? V() : it->second;",
					"  }",
					"  void set(std::string key, V value) { __values[key] = value; }",
					"  std::shared_ptr<__hxhx_iterator<std::string>> keys() {",
					"    std::vector<std::string> out;",
					"    for (const auto& item : __values) out.push_back(item.first);",
					"    return std::make_shared<__hxhx_stringmap_key_iterator>(std::move(out));",
					"  }",
					"  std::string toString() { return std::string(\"[object StringMap]\"); }",
					"};"
				];
			case "Date":
				["struct Date {", "  std::string toString() { return std::string(); }", "};"];
			case _:
				null;
		}
	}

	public static function missingMethodReturnType(cleanClassName:String, cleanMethodName:String):String {
		return switch (cleanClassName) {
			case "IMap":
				switch (cleanMethodName) {
					case "get":
						"std::optional<std::string>";
					case "set" | "clear":
						"void";
					case "exists" | "remove":
						"bool";
					case "keys" | "iterator":
						"std::shared_ptr<__hxhx_iterator<std::string>>";
					case "keyValueIterator":
						"std::shared_ptr<KeyValueIterator>";
					case "copy":
						"std::shared_ptr<IMap>";
					case "toString":
						"std::string";
					case _:
						"";
				}
			case "StringMap":
				switch (cleanMethodName) {
					case "get" | "toString":
						"std::string";
					case "set":
						"void";
					case "keys":
						"std::shared_ptr<__hxhx_iterator<std::string>>";
					case _:
						"";
				}
			case _:
				"";
		}
	}

	public static function anySupportLines():Array<String> {
		return [
			"struct Any {",
			"  std::any __value;",
			"  Any() = default;",
			"  template<typename T>",
			"  Any(T value) : __value(value) {}",
			"  template<typename T>",
			"  T __promote() const {",
			"    if constexpr (std::is_same_v<T, std::any>) return __value;",
			"    else if constexpr (std::is_same_v<T, std::string>) return __hxhx_stringify(__value);",
			"    else if (__value.has_value() && __value.type() == typeid(T)) return std::any_cast<T>(__value);",
			"    else return T{};",
			"  }",
			"  std::string toString() const { return __hxhx_stringify(__value); }",
			"};"
		];
	}

	public static function fpReinterpretLines():Array<String> {
		return [
			"static double __hxhx_reinterpret_le_int32_as_float32(int value) {",
			"  std::uint32_t bits = static_cast<std::uint32_t>(value);",
			"  float out = 0;",
			"  std::memcpy(&out, &bits, sizeof(out));",
			"  return static_cast<double>(out);",
			"}",
			"",
			"static int __hxhx_reinterpret_float32_as_le_int32(double value) {",
			"  float narrowed = static_cast<float>(value);",
			"  std::uint32_t bits = 0;",
			"  std::memcpy(&bits, &narrowed, sizeof(bits));",
			"  return static_cast<int>(bits);",
			"}",
			"",
			"static double __hxhx_reinterpret_le_int32s_as_float64(int low, int high) {",
			"  std::uint64_t bits = (static_cast<std::uint64_t>(static_cast<std::uint32_t>(high)) << 32) | static_cast<std::uint32_t>(low);",
			"  double out = 0;",
			"  std::memcpy(&out, &bits, sizeof(out));",
			"  return out;",
			"}",
			"",
			"static int __hxhx_reinterpret_float64_as_le_int32_low(double value) {",
			"  std::uint64_t bits = 0;",
			"  std::memcpy(&bits, &value, sizeof(bits));",
			"  return static_cast<int>(static_cast<std::uint32_t>(bits & 0xFFFFFFFFULL));",
			"}",
			"",
			"static int __hxhx_reinterpret_float64_as_le_int32_high(double value) {",
			"  std::uint64_t bits = 0;",
			"  std::memcpy(&bits, &value, sizeof(bits));",
			"  return static_cast<int>(static_cast<std::uint32_t>((bits >> 32) & 0xFFFFFFFFULL));",
			"}"
		];
	}

	public static function dateIntrinsicLines():Array<String> {
		return [
			"static double __hxhx_utc_date(int year, int month, int day, int hour, int min, int sec) {",
			"  std::tm tm = {};",
			"  tm.tm_year = year - 1900;",
			"  tm.tm_mon = month;",
			"  tm.tm_mday = day;",
			"  tm.tm_hour = hour;",
			"  tm.tm_min = min;",
			"  tm.tm_sec = sec;",
			"#if defined(_WIN32)",
			"  return static_cast<double>(_mkgmtime(&tm));",
			"#else",
			"  return static_cast<double>(timegm(&tm));",
			"#endif",
			"}"
		];
	}

	public static function stdIntrinsicLines():Array<String> {
		return [
			"static std::optional<int> __hxhx_parse_int(const std::string& value) {",
			"  try {",
			"    std::size_t parsed = 0;",
			"    int base = (value.size() >= 2 && value[0] == '0' && (value[1] == 'x' || value[1] == 'X')) ? 16 : 10;",
			"    int out = std::stoi(value, &parsed, base);",
			"    return parsed == 0 ? std::nullopt : std::optional<int>(out);",
			"  } catch (...) {",
			"    return std::nullopt;",
			"  }",
			"}"
		];
	}

	public static function vectorSupportLines():Array<String> {
		return [
			"template<typename T>",
			"static T __hxhx_vector_get(const std::vector<T>& values, int index) {",
			"  if (index < 0 || static_cast<std::size_t>(index) >= values.size()) return T{};",
			"  return values[static_cast<std::size_t>(index)];",
			"}",
			"",
			"template<typename T>",
			"static T __hxhx_vector_pop(std::vector<T>& values) {",
			"  if (values.empty()) return T{};",
			"  T value = values.back();",
			"  values.pop_back();",
			"  return value;",
			"}",
			"",
			"template<typename T, typename U>",
			"static bool __hxhx_vector_value_eq(const T& value, const U& expected) {",
			"  return value == expected;",
			"}",
			"",
			"template<typename T>",
			"static bool __hxhx_vector_value_eq(const std::optional<T>& value, const T& expected) {",
			"  return value.has_value() && value.value() == expected;",
			"}",
			"",
			"template<typename T>",
			"static bool __hxhx_vector_value_eq(const std::optional<T>& value, std::nullptr_t) {",
			"  return !value.has_value();",
			"}",
			"",
			"template<typename T, typename U>",
			"static bool __hxhx_vector_remove(std::vector<T>& values, const U& needle) {",
			"  for (auto it = values.begin(); it != values.end(); ++it) {",
			"    if (__hxhx_vector_value_eq(*it, needle)) {",
			"      values.erase(it);",
			"      return true;",
			"    }",
			"  }",
			"  return false;",
			"}",
			"",
			"template<typename T>",
			"static std::vector<T> __hxhx_vector_splice(std::vector<T>& values, int pos, int len) {",
			"  int size = static_cast<int>(values.size());",
			"  int start = pos < 0 ? size + pos : pos;",
			"  if (start < 0) start = 0;",
			"  if (start > size) start = size;",
			"  int count = len < 0 ? 0 : len;",
			"  int end = start + count;",
			"  if (end > size) end = size;",
			"  auto first = values.begin() + start;",
			"  auto last = values.begin() + end;",
			"  std::vector<T> removed(first, last);",
			"  values.erase(first, last);",
			"  return removed;",
			"}"
		];
	}

	public static function sysEventLoopLines():Array<String> {
		return [
			"template<typename T>",
			"static T __hxhx_shift(std::vector<T>& values) {",
			"  T value = values.front();",
			"  values.erase(values.begin());",
			"  return value;",
			"}",
			"",
			"struct Timer {",
			"  static double stamp() {",
			"    using clock = std::chrono::steady_clock;",
			"    static const auto start = clock::now();",
			"    return std::chrono::duration<double>(clock::now() - start).count();",
			"  }",
			"  static std::shared_ptr<Timer> delay(std::function<void()> f, double ms) {",
			"    (void)f;",
			"    (void)ms;",
			"    return std::make_shared<Timer>();",
			"  }",
			"  void stop() {}",
			"};",
			"",
			"struct __hxhx_http_bytes {",
			"  std::vector<int> values;",
			"  std::size_t size() const { return values.size(); }",
			"  int get(int index) const { return index < 0 || static_cast<std::size_t>(index) >= values.size() ? 0 : values[static_cast<std::size_t>(index)]; }",
			"};",
			"",
			"struct Http {",
			"  std::function<void(std::string)> onData = nullptr;",
			"  std::function<void(std::string)> onError = nullptr;",
			"  std::function<void(__hxhx_http_bytes)> onBytes = nullptr;",
			"  explicit Http(std::string url = std::string()) { (void)url; }",
			"  void setPostData(std::string value) { (void)value; }",
			"  template<typename T>",
			"  void setPostBytes(T value) { (void)value; }",
			"  void request() {}",
			"};",
			"",
			"struct Lock {",
			"  void acquire() {}",
			"  bool wait(std::optional<double> = std::nullopt) { return true; }",
			"  void release() {}",
			"};",
			"",
			"struct Mutex {",
			"  void acquire() {}",
			"  bool tryAcquire() { return true; }",
			"  void release() {}",
			"};",
			"",
			"struct MainLoop;",
			"",
			"struct MainEvent {",
			"  std::function<void()> f;",
			"  std::shared_ptr<MainEvent> prev = nullptr;",
			"  std::shared_ptr<MainEvent> next = nullptr;",
			"  double nextRun = -std::numeric_limits<double>::infinity();",
			"  int priority = 0;",
			"  bool isMain = false;",
			"  MainEvent(std::function<void()> f = nullptr, std::optional<int> priority = std::nullopt) : f(f), priority(priority.value_or(0)) {}",
			"  void delay(std::optional<double> t = std::nullopt);",
			"  void stop();",
			"  void wakeup() {}",
			"};",
			"",
			"struct MainLoop {",
			"  inline static std::shared_ptr<MainEvent> pending = nullptr;",
			"  static std::shared_ptr<MainEvent> add(std::function<void()> f, std::optional<int> priority = std::nullopt) {",
			"    auto event = std::make_shared<MainEvent>(f, priority);",
			"    event->next = pending;",
			"    if (pending != nullptr) pending->prev = event;",
			"    pending = event;",
			"    return event;",
			"  }",
			"  static bool hasEvents() { return pending != nullptr; }",
			"  static void sortEvents() {}",
			"  static double tick() {",
			"    sortEvents();",
			"    auto event = pending;",
			"    if (event == nullptr) return -std::numeric_limits<double>::infinity();",
			"    pending = event->next;",
			"    if (pending != nullptr) pending->prev = nullptr;",
			"    event->next = nullptr;",
			"    if (event->f) event->f();",
			"    return pending == nullptr ? -std::numeric_limits<double>::infinity() : pending->nextRun;",
			"  }",
			"};",
			"",
			"inline void MainEvent::delay(std::optional<double> t) {",
			"  nextRun = !t.has_value() ? -std::numeric_limits<double>::infinity() : Timer::stamp() + t.value();",
			"}",
			"",
			"inline void MainEvent::stop() {",
			"  if (prev != nullptr) prev->next = next;",
			"  if (next != nullptr) next->prev = prev;",
			"  if (MainLoop::pending.get() == this) MainLoop::pending = next;",
			"  prev = nullptr;",
			"  next = nullptr;",
			"}",
			"",
			"struct EntryPoint {",
			"  inline static std::shared_ptr<Lock> sleepLock = std::make_shared<Lock>();",
			"  inline static std::shared_ptr<Mutex> mutex = std::make_shared<Mutex>();",
			"  inline static int threadCount = 0;",
			"  inline static std::vector<std::function<void()>> pending = {};",
			"  static void wakeup() { sleepLock->release(); }",
			"  static void runInMainThread(std::function<void()> f) {",
			"    mutex->acquire();",
			"    pending.push_back(f);",
			"    mutex->release();",
			"    wakeup();",
			"  }",
			"  static void addThread(std::function<void()> f) {",
			"    mutex->acquire();",
			"    threadCount++;",
			"    mutex->release();",
			"    if (f) f();",
			"    mutex->acquire();",
			"    threadCount--;",
			"    mutex->release();",
			"  }",
			"  static double processEvents() {",
			"    mutex->acquire();",
			"    while (!pending.empty()) {",
			"      auto f = __hxhx_shift(pending);",
			"      mutex->release();",
			"      if (f) f();",
			"      mutex->acquire();",
			"    }",
			"    mutex->release();",
			"    double time = MainLoop::tick();",
			"    return (!MainLoop::hasEvents() && threadCount == 0) ? -std::numeric_limits<double>::infinity() : time;",
			"  }",
			"};"
		];
	}

	public static function rttiMetaLines():Array<String> {
		return [
			"template<typename TResult, typename T>",
			"static TResult __hxhx_meta_get_as(const T&) {",
			"  return TResult{};",
			"}",
			"",
			"template<typename TResult, typename T>",
			"static TResult __hxhx_meta_section_as(const T&, const std::string&) {",
			"  return TResult{};",
			"}",
			"",
			"static std::any __hxhx_reflect_get_property_any(const std::any&, const std::string&) {",
			"  return std::any();",
			"}",
			"",
			"static bool __hxhx_reflect_has_field_any(const std::any&, const std::string&) {",
			"  return false;",
			"}",
			"",
			"template<typename TObject>",
			"static std::any __hxhx_reflect_field(const TObject&, const std::string&) {",
			"  return std::any();",
			"}",
			"",
			"template<typename TObject, typename TValue>",
			"static void __hxhx_reflect_set_field(TObject&, const std::string&, const TValue&) {",
			"}",
			"",
			"template<typename TObject, typename TFunc, typename TArgs>",
			"static std::any __hxhx_reflect_call_method(const TObject&, const TFunc&, const TArgs&) {",
			"  return std::any();",
			"}",
			"",
			"template<typename T>",
			"static bool __hxhx_reflect_is_function(const T&) {",
			"  return false;",
			"}",
			"",
			"template<typename R, typename... Args>",
			"static bool __hxhx_reflect_is_function(const std::function<R(Args...)>&) {",
			"  return true;",
			"}",
			"",
			"template<typename A, typename B>",
			"static bool __hxhx_reflect_compare_methods(const A&, const B&) {",
			"  return false;",
			"}"
		];
	}

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
			"}",
			"",
			"static double __hxhx_any_double(const std::any& value) {",
			"  if (!value.has_value()) return 0.0;",
			"  if (value.type() == typeid(double)) return std::any_cast<double>(value);",
			"  if (value.type() == typeid(float)) return static_cast<double>(std::any_cast<float>(value));",
			"  if (value.type() == typeid(int)) return static_cast<double>(std::any_cast<int>(value));",
			"  if (value.type() == typeid(bool)) return std::any_cast<bool>(value) ? 1.0 : 0.0;",
			"  if (value.type() == typeid(std::string)) {",
			"    try {",
			"      return std::stod(std::any_cast<std::string>(value));",
			"    } catch (...) {",
			"      return 0.0;",
			"    }",
			"  }",
			"  return 0.0;",
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
