"""Storage fixtures only: never inspect, move, or remove the user's real stores."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
from contextlib import closing
from unittest.mock import patch

from . import storage


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="fan-storage-fixture-")
        self.root = Path(self.temporary.name).resolve()
        self.source = self.root / "source"
        self.destination = self.root / "destination"
        self.source.mkdir()
        self.snapshots = self.source / "snapshots"
        (self.snapshots / "cycle").mkdir(parents=True)
        (self.snapshots / "empty").mkdir()
        (self.snapshots / "cycle" / "frame.png").write_bytes(b"fixture-image\x00" * 800)

    def tearDown(self):
        # Remove fixture junctions explicitly before TemporaryDirectory cleanup;
        # never allow a recursive cleanup to traverse their external targets.
        for name in ("snapshots", "snapshots.fan-original-junction-job"):
            path = self.source / name
            if os.path.lexists(path) and storage._is_reparse(path):
                path.rmdir()
        self.temporary.cleanup()

    def database(self, role="tracking", *, wal=False):
        path = self.source / storage.DATABASES[role]
        connection = sqlite3.connect(path)
        if wal:
            connection.execute("PRAGMA journal_mode=WAL")
        connection.executescript("CREATE TABLE learned(id INTEGER PRIMARY KEY, value TEXT);"
                                 "CREATE INDEX learned_value ON learned(value);"
                                 "CREATE TRIGGER learned_insert AFTER INSERT ON learned BEGIN SELECT 1; END;"
                                 "PRAGMA user_version=42;")
        connection.execute("INSERT INTO learned(value) VALUES(?)", ("wal-backed insight",))
        connection.commit()
        return path, connection

    def read_value(self, path):
        with closing(sqlite3.connect(path)) as database:
            return database.execute("SELECT value FROM learned").fetchall()

    def test_export_is_wal_aware_and_preserves_schema_without_touching_sources(self):
        path, live = self.database(wal=True)
        try:
            self.assertGreater(Path(str(path) + "-wal").stat().st_size, 0)
            result = storage.prepare_export({"tracking": path}, self.snapshots, self.destination, job_id="wal-export")
            self.assertEqual(self.read_value(result["targets"]["tracking"]), [("wal-backed insight",)])
            backup = sqlite3.connect(result["targets"]["tracking"])
            try:
                self.assertEqual(backup.execute("PRAGMA user_version").fetchone()[0], 42)
                self.assertIsNotNone(backup.execute("SELECT name FROM sqlite_master WHERE type='trigger'").fetchone())
            finally:
                backup.close()
            self.assertTrue(path.exists())
            self.assertEqual((self.snapshots / "cycle" / "frame.png").read_bytes(), b"fixture-image\x00" * 800)
            self.assertTrue(storage.verify_bundle(result["manifest"])["ok"])
            self.assertFalse(Path(result["targets"]["tracking"] + "-wal").exists())
        finally:
            live.close()

    def test_snapshot_only_export_and_database_roles(self):
        result = storage.prepare_export({}, self.snapshots, self.destination, job_id="snapshots-only")
        self.assertEqual(result["targets"], {})
        self.assertIsNotNone(result["snapshots"])
        self.assertTrue((Path(result["snapshots"]["target"]) / "empty").is_dir())
        self.assertTrue(storage.verify_bundle(result["manifest"])["ok"])
        path, database = self.database("catalog")
        database.close()
        result = storage.prepare_export({"catalog": path}, None, self.destination, job_id="catalog-only")
        self.assertEqual(set(result["targets"]), {"catalog"})
        self.assertIsNone(result["snapshots"])

    def test_cancel_stage_retains_sources_and_resumes(self):
        original = b"snapshot-data" * (300000)
        (self.snapshots / "cycle" / "large.png").write_bytes(original)
        cancel = self.root / "cancel"

        def stop(event):
            if event["phase"] == "snapshot-copy":
                cancel.write_text("cancel", encoding="utf-8")

        with self.assertRaises(storage.Cancelled):
            storage.prepare_export({}, self.snapshots, self.destination, job_id="resume", progress=stop, cancel_file=cancel)
        self.assertEqual((self.snapshots / "cycle" / "large.png").read_bytes(), original)
        cancel.unlink()
        result = storage.prepare_export({}, self.snapshots, self.destination, job_id="resume", cancel_file=cancel)
        self.assertTrue(storage.verify_bundle(result["manifest"])["ok"])
        self.assertEqual((Path(result["snapshots"]["target"]) / "cycle" / "large.png").read_bytes(), original)

    def test_destination_tamper_and_source_nested_destination_rejected(self):
        result = storage.prepare_export({}, self.snapshots, self.destination, job_id="tamper")
        (Path(result["snapshots"]["target"]) / "cycle" / "frame.png").write_bytes(b"changed")
        with self.assertRaises(storage.StorageError):
            storage.verify_bundle(result["manifest"])
        with self.assertRaises(storage.StorageError):
            storage.prepare_export({}, self.snapshots, self.snapshots / "child", job_id="nested")

    def test_foreign_staging_and_unmanaged_database_rejected(self):
        partial = self.destination / "Fan-export-" / ".foreign.partial"
        partial.mkdir(parents=True)
        (partial / "unrelated.txt").write_text("keep", encoding="utf-8")
        with self.assertRaises(storage.StorageError):
            storage.prepare_export({}, self.snapshots, self.destination, job_id="foreign")
        self.assertTrue((partial / "unrelated.txt").exists())
        path = self.source / "Managerv7.sqlite"
        sqlite3.connect(path).close()
        with self.assertRaises(storage.StorageError):
            storage.prepare_export({"manager": path}, None, self.destination)

    def test_integrity_verification_detects_corrupt_sqlite_pages(self):
        path, database = self.database()
        database.execute("PRAGMA writable_schema=ON")
        database.execute("UPDATE sqlite_master SET rootpage=999999 WHERE name='learned'")
        database.commit()
        database.close()
        with self.assertRaises((storage.StorageError, sqlite3.DatabaseError)):
            storage.prepare_export({"tracking": path}, None, self.destination, job_id="corrupt")
        self.assertTrue(path.exists())
        self.assertFalse((self.destination / "Fan-export-" / "corrupt" / "manifest.json").exists())

    def test_integrity_phase_is_cancellable(self):
        path, database = self.database()
        database.close()
        cancel = self.root / "integrity-cancel"

        def stop(event):
            if event["phase"] == "database-integrity":
                cancel.write_text("stop", encoding="utf-8")

        with self.assertRaises(storage.Cancelled):
            storage.prepare_export({"tracking": path}, None, self.destination, job_id="integrity-cancel", progress=stop, cancel_file=cancel)
        self.assertTrue(path.exists())

    @unittest.skipUnless(os.name == "nt", "Native Windows exclusive-access check")
    def test_offload_refuses_another_open_database_handle(self):
        path, live = self.database(wal=True)
        try:
            with self.assertRaisesRegex(storage.StorageError, "still in use"):
                storage.prepare_export({"tracking": path}, None, self.destination, mode="offload", job_id="busy")
            self.assertTrue(path.exists())
        finally:
            live.close()

    @unittest.skipUnless(os.name == "nt", "Native Windows offload fixture")
    def test_database_cleanup_requires_confirmed_targets_and_unchanged_original(self):
        path, database = self.database()
        database.close()
        result = storage.prepare_export({"tracking": path}, None, self.destination, mode="offload", job_id="database-offload")
        with self.assertRaises(storage.StorageError):
            storage.cleanup_offloaded_databases(result["manifest"], {"tracking": path})
        self.assertTrue(path.exists())
        cleanup = storage.cleanup_offloaded_databases(result["manifest"], result["targets"])
        self.assertEqual(len(cleanup["removed"]), 1)
        self.assertFalse(path.exists())
        self.assertEqual(self.read_value(result["targets"]["tracking"]), [("wal-backed insight",)])

    @unittest.skipUnless(os.name == "nt", "Native Windows offload fixture")
    def test_database_change_after_stage_refuses_cleanup(self):
        path, database = self.database()
        database.close()
        result = storage.prepare_export({"tracking": path}, None, self.destination, mode="offload", job_id="changed-database")
        with sqlite3.connect(path) as database:
            database.execute("INSERT INTO learned(value) VALUES('new insight')")
        database.close()
        with self.assertRaisesRegex(storage.StorageError, "changed after staging"):
            storage.cleanup_offloaded_databases(result["manifest"], result["targets"])
        self.assertTrue(path.exists())

    @unittest.skipUnless(os.name == "nt", "Persistent Windows original-file guard")
    def test_cutover_guard_blocks_new_sqlite_readers_and_allows_confirmed_unlink(self):
        path, database = self.database()
        database.close()
        result = storage.prepare_export({"tracking": path}, None, self.destination, mode="offload", job_id="guarded-offload")
        with storage.hold_originals(result["manifest"]) as guarded:
            self.assertTrue(guarded["guarded_paths"])
            with self.assertRaises(sqlite3.OperationalError):
                storage._readonly_database(path)
            self.assertTrue(storage.cleanup_offloaded_databases(result["manifest"], result["targets"])["ok"])
        self.assertFalse(path.exists())
        self.assertEqual(self.read_value(result["targets"]["tracking"]), [("wal-backed insight",)])

    @unittest.skipUnless(os.name == "nt", "Persistent Windows original-file guard")
    def test_cutover_guard_rechecks_source_changes_and_other_readers(self):
        path, database = self.database()
        database.close()
        result = storage.prepare_export({"tracking": path}, None, self.destination, mode="offload", job_id="guard-race")
        reader = sqlite3.connect(path)
        try:
            with self.assertRaisesRegex(storage.StorageError, "still in use before cutover"):
                with storage.hold_originals(result["manifest"]):
                    self.fail("A competing reader was not blocked")
        finally:
            reader.close()
        with sqlite3.connect(path) as writer:
            writer.execute("INSERT INTO learned(value) VALUES('late write')")
        writer.close()
        with self.assertRaisesRegex(storage.StorageError, "changed before cutover"):
            with storage.hold_originals(result["manifest"]):
                self.fail("A source write after staging was not detected")
        self.assertTrue(path.exists())

    @unittest.skipUnless(os.name == "nt", "Native Windows junction fixture")
    def test_snapshot_commit_preserves_absolute_path_then_rolls_back(self):
        result = storage.prepare_export({}, self.snapshots, self.destination, mode="offload", job_id="junction-job")
        journal = storage.commit_snapshots(result["manifest"])
        self.assertTrue(storage._is_reparse(self.snapshots))
        self.assertEqual(self.snapshots.resolve(), Path(result["snapshots"]["target"]).resolve())
        self.assertEqual((self.snapshots / "cycle" / "frame.png").read_bytes(), b"fixture-image\x00" * 800)
        self.assertTrue(Path(journal["backup"]).is_dir())
        storage.rollback_snapshots(result["manifest"], journal)
        self.assertFalse(storage._is_reparse(self.snapshots))
        self.assertTrue((self.snapshots / "cycle" / "frame.png").exists())

    @unittest.skipUnless(os.name == "nt", "Native Windows junction fixture")
    def test_snapshot_cutover_failure_restores_original(self):
        result = storage.prepare_export({}, self.snapshots, self.destination, mode="offload", job_id="junction-job")
        with patch.object(storage, "_junction", side_effect=storage.StorageError("simulated junction error")):
            with self.assertRaisesRegex(storage.StorageError, "simulated"):
                storage.commit_snapshots(result["manifest"])
        self.assertTrue((self.snapshots / "cycle" / "frame.png").exists())
        self.assertFalse(storage._is_reparse(self.snapshots))
        self.assertEqual(json.loads((Path(result["bundle"]) / "snapshot-cutover.json").read_text())["status"], "rolled-back")

    @unittest.skipUnless(os.name == "nt", "Native Windows junction fixture")
    def test_snapshot_cleanup_frees_original_and_keeps_legacy_path(self):
        result = storage.prepare_export({}, self.snapshots, self.destination, mode="offload", job_id="junction-job")
        journal = storage.commit_snapshots(result["manifest"])
        cleanup = storage.cleanup_offloaded_snapshots(result["manifest"], journal)
        self.assertEqual(cleanup["removed"], 1)
        self.assertFalse(Path(journal["backup"]).exists())
        self.assertTrue((self.snapshots / "cycle" / "frame.png").exists())
        with self.assertRaises(storage.StorageError):
            storage.rollback_snapshots(result["manifest"])

    @unittest.skipUnless(os.name == "nt", "Native Windows junction fixture")
    def test_source_snapshot_change_refuses_cutover(self):
        result = storage.prepare_export({}, self.snapshots, self.destination, mode="offload", job_id="changed-snapshot")
        (self.snapshots / "new.png").write_bytes(b"new snapshot")
        with self.assertRaisesRegex(storage.StorageError, "gained or lost"):
            storage.commit_snapshots(result["manifest"])
        self.assertTrue((self.snapshots / "new.png").exists())
        self.assertFalse(storage._is_reparse(self.snapshots))

    @unittest.skipUnless(os.name == "nt", "Native Windows junction fixture")
    def test_cleanup_can_resume_after_partial_snapshot_deletion(self):
        (self.snapshots / "cycle" / "second.png").write_bytes(b"second fixture image")
        result = storage.prepare_export({}, self.snapshots, self.destination, mode="offload", job_id="junction-job")
        storage.commit_snapshots(result["manifest"])
        original_unlink = Path.unlink
        interrupted = []

        def fail_second(path, *args, **kwargs):
            if path.name == "second.png" and ".fan-original-" in str(path) and not interrupted:
                interrupted.append(True)
                raise OSError("simulated cleanup interruption")
            return original_unlink(path, *args, **kwargs)

        with patch.object(Path, "unlink", fail_second):
            with self.assertRaisesRegex(OSError, "interruption"):
                storage.cleanup_offloaded_snapshots(result["manifest"])
        self.assertTrue(storage.cleanup_offloaded_snapshots(result["manifest"])["ok"])
        self.assertTrue((self.snapshots / "cycle" / "second.png").exists())
        self.assertFalse((self.source / "snapshots.fan-original-junction-job").exists())

    @unittest.skipUnless(os.name == "nt", "Native Windows offload fixture")
    def test_cleanup_can_resume_owned_sidecar_after_main_database_removed(self):
        path, database = self.database()
        database.close()
        sidecar = Path(str(path) + "-shm")
        sidecar.write_bytes(b"fixture coordination sidecar")
        result = storage.prepare_export({"tracking": path}, None, self.destination, mode="offload", job_id="sidecar-cleanup")
        original_unlink = Path.unlink
        interrupted = []

        def fail_sidecar(target, *args, **kwargs):
            if target == sidecar and not interrupted:
                interrupted.append(True)
                raise OSError("simulated sidecar cleanup interruption")
            return original_unlink(target, *args, **kwargs)

        with patch.object(Path, "unlink", fail_sidecar):
            with self.assertRaisesRegex(OSError, "interruption"):
                storage.cleanup_offloaded_databases(result["manifest"], result["targets"])
        self.assertFalse(path.exists())
        self.assertTrue(sidecar.exists())
        self.assertTrue(storage.cleanup_offloaded_databases(result["manifest"], result["targets"])["ok"])
        self.assertFalse(sidecar.exists())

    @unittest.skipUnless(os.name == "nt", "Native Windows junction fixture")
    def test_already_offloaded_snapshots_can_move_again_with_same_legacy_path(self):
        first = storage.prepare_export({}, self.snapshots, self.destination, mode="offload", job_id="junction-job")
        storage.commit_snapshots(first["manifest"])
        storage.cleanup_offloaded_snapshots(first["manifest"])
        second = storage.prepare_export({}, self.snapshots, self.destination, mode="offload", job_id="junction-job-2")
        journal = storage.commit_snapshots(second["manifest"])
        self.assertTrue(journal["source_was_junction"])
        storage.cleanup_offloaded_snapshots(second["manifest"])
        self.assertEqual(self.snapshots.resolve(), Path(second["snapshots"]["target"]).resolve())
        self.assertFalse(Path(first["snapshots"]["target"]).exists())
        self.assertTrue((self.snapshots / "cycle" / "frame.png").is_file())

    @unittest.skipUnless(os.name == "nt", "Native Windows junction fixture")
    def test_destination_parent_junction_is_not_followed_on_resume(self):
        partial = self.destination / "Fan-export-" / ".parent-link.partial"
        partial.mkdir(parents=True)
        storage._atomic_json(partial / storage.OWNER, {"version": 1, "job_id": "parent-link", "mode": "export"})
        unrelated = self.root / "unrelated"
        unrelated.mkdir()
        link = partial / "snapshots"
        storage._junction(link, unrelated)
        try:
            with self.assertRaisesRegex(storage.StorageError, "link/junction"):
                storage.prepare_export({}, self.snapshots, self.destination, job_id="parent-link")
            self.assertEqual(list(unrelated.iterdir()), [])
        finally:
            link.rmdir()


if __name__ == "__main__":
    unittest.main()
