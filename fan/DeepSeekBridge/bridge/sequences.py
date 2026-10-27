"""One durable performed-sequence record per prompt; the event ledger holds steps."""
def initialize(db):
    db.execute('CREATE TABLE IF NOT EXISTS automation_sequence ('
               'task_id TEXT PRIMARY KEY,prompt TEXT,created_at TEXT,status TEXT,finished_at TEXT DEFAULT "")')


def record(db, task_id, prompt, created_at):
    initialize(db)
    db.execute('INSERT OR IGNORE INTO automation_sequence(task_id,prompt,created_at,status) VALUES(?,?,?,?)',
               (task_id, prompt, created_at, 'queued'))


def update(db, task_id, status, at):
    initialize(db)
    db.execute('UPDATE automation_sequence SET status=?,finished_at=? WHERE task_id=?',
               (status, at if status in ('complete', 'error', 'cancelled') else '', task_id))
