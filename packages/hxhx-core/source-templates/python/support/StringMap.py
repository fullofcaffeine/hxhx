class StringMap(dict):
    def set(self, key, value):
        self[key] = value

    def get(self, key):
        return dict.get(self, key, None)

    def exists(self, key):
        return key in self

    def remove(self, key):
        if key not in self:
            return False
        del self[key]
        return True

    def keys(self):
        return list(dict.keys(self))

    def iterator(self):
        return list(dict.values(self))
