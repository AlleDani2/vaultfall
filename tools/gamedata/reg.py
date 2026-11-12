"""Registro centrale dei contenuti generati (oggetti, azioni, ecc.)."""
from collections import OrderedDict


class Registry:
    def __init__(self):
        self.items = OrderedDict()
        self.actions = OrderedDict()       # azioni di mansione (raccolta/creazione/borseggio/coltivazione)
        self.tables = OrderedDict()        # altre tabelle: monsters, zones, crates, quests, ...

    def item(self, id_, **kw):
        if id_ in self.items:
            raise ValueError(f"oggetto duplicato: {id_}")
        d = OrderedDict(id=id_)
        d.update(kw)
        d.setdefault("stackable", True)
        d.setdefault("tradeable", True)
        d.setdefault("icon", f"res://assets/icons/items/{id_}.png")
        self.items[id_] = d
        return d

    def action(self, id_, **kw):
        if id_ in self.actions:
            raise ValueError(f"azione duplicata: {id_}")
        d = OrderedDict(id=id_)
        d.update(kw)
        self.actions[id_] = d
        return d

    def table(self, name):
        return self.tables.setdefault(name, [])

    def get(self, id_):
        return self.items[id_]

    def value(self, id_):
        return self.items[id_]["value"]


R = Registry()
