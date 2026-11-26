"""Fan knowledge base: documents -> sentence elements -> self-discovered head topics.

Everything is local. Ingested text is split into sentences ("elements"), each
normalized to word roots, embedded with Fan's own corpus-trained model
(:mod:`embed`), stored in a SQLite vector index (:mod:`store`), assigned to one
of up to 20 automatically discovered head topics (:mod:`heads`) and sequenced
from simple to complex. :mod:`model` turns that into a compact per-head
"knowledge pack" and answers questions by routing through the heads.
"""

VERSION = "1.0"
