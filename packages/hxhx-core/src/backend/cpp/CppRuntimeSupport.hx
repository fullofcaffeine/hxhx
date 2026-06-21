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
