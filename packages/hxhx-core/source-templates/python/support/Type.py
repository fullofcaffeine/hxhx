class Type:
    @staticmethod
    def resolveClass(name):
        if name is None:
            return None
        return globals().get(str(name).split(".")[-1], None)

    @staticmethod
    def getClass(value):
        if value is None:
            return None
        return value if isinstance(value, type) else value.__class__

    @staticmethod
    def getClassName(cls):
        if cls is None:
            return None
        target = cls if isinstance(cls, type) else Type.getClass(cls)
        return getattr(target, "__name__", str(target))

    @staticmethod
    def getInstanceFields(cls):
        if cls is None:
            return Array()
        fields = []
        for current in reversed(getattr(cls, "__mro__", [cls])):
            for name, value in getattr(current, "__dict__", {}).items():
                if name.startswith("__") or isinstance(value, (staticmethod, classmethod)):
                    continue
                if name not in fields:
                    fields.append(name)
        return Array(fields)

    @staticmethod
    def getClassFields(cls):
        if cls is None:
            return Array()
        fields = []
        for current in reversed(getattr(cls, "__mro__", [cls])):
            for name, value in getattr(current, "__dict__", {}).items():
                if name.startswith("__") or not isinstance(value, (staticmethod, classmethod)):
                    continue
                if name not in fields:
                    fields.append(name)
        return Array(fields)
