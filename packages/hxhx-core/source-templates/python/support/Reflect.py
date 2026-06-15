class Reflect:
    @staticmethod
    def field(obj, name):
        if obj is None:
            return None
        if isinstance(obj, dict):
            return obj.get(name, None)
        return getattr(obj, name, None)

    @staticmethod
    def getProperty(obj, name):
        return Reflect.field(obj, name)

    @staticmethod
    def isFunction(value):
        return callable(value)

    @staticmethod
    def isObject(value):
        return value is not None and not callable(value) and not isinstance(value, (bool, int, float))

    @staticmethod
    def compare(left, right):
        return (left > right) - (left < right)
