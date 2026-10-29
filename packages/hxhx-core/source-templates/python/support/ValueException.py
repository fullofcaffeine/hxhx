class ValueException(Exception):
    _hx_class_name = "haxe.ValueException"
    def __init__(self, value=None):
        self.value = value
        self.stack = []
        super().__init__(str(value))

    @staticmethod
    def thrown(value):
        return ValueException(value)
