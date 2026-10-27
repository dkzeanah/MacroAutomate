"""Offline behavior tests for the creator operations companion."""

from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import creator_ops as ops


def sample_brief(*, hook: str = "A practical hook") -> ops.ContentBrief:
    return ops.ContentBrief(
        title="A sourced creator brief",
        hook=hook,
        thesis="The creator states one defensible position.",
        opposing_view="A reasonable person can prefer the competing tradeoff.",
        practical_value="The audience receives a three-step checklist.",
        evidence_needed=("Verify the current platform rule.",),
        talking_points=("Define the problem.", "Compare the tradeoff.", "Offer an action."),
        call_to_action="What evidence changed your view?",
        safety_check="No invented facts or personal targeting.",
        format="short video",
        variant_a_hook="Lead with the cost.",
        variant_b_hook="Lead with the opportunity.",
    )


class FakeOllamaClient:
    def chat_json(self, **_kwargs: object) -> dict[str, object]:
        brief = sample_brief()
        return {
            "title": brief.title,
            "hook": brief.hook,
            "thesis": brief.thesis,
            "opposing_view": brief.opposing_view,
            "practical_value": brief.practical_value,
            "evidence_needed": list(brief.evidence_needed),
            "talking_points": list(brief.talking_points),
            "call_to_action": brief.call_to_action,
            "safety_check": brief.safety_check,
            "format": brief.format,
            "variant_a_hook": brief.variant_a_hook,
            "variant_b_hook": brief.variant_b_hook,
        }


class FailingPublisher(ops.OfficialPublisher):
    def _publish_facebook(self, destination, payload, token):  # type: ignore[no-untyped-def]
        raise ops.PublishingError("simulated official API timeout")


class CreatorOpsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.store = ops.CreatorStore(Path(self.directory.name) / "creator.db")

    def tearDown(self) -> None:
        self.store.close()
        self.directory.cleanup()

    def _content(self, *, experiment: str = "", variant: str = "") -> int:
        topic_id = int(self.store.list_topics()[0]["id"])
        return self.store.create_content(
            topic_id=topic_id,
            brief=sample_brief(),
            source_urls=("https://example.com/source",),
            experiment_key=experiment,
            variant_label=variant,
        )

    def _account(self, platform: str = "facebook") -> int:
        return self.store.add_account(
            platform=platform,
            display_name="Official test account",
            handle="@test",
            remote_id="remote-123",
            token_env="TEST_PLATFORM_TOKEN",
        )

    def test_database_seeds_ten_safe_topic_lanes(self) -> None:
        topics = self.store.list_topics()
        self.assertEqual(len(topics), 10)
        all_text = " ".join(str(value) for row in topics for value in row).lower()
        self.assertIn("privacy", all_text)
        self.assertIn("originality", all_text)
        self.assertNotIn("fake reddit", all_text)

    def test_schedule_requires_current_human_approval(self) -> None:
        content_id = self._content()
        account_id = self._account()
        with self.assertRaisesRegex(ops.CreatorOpsError, "Approve"):
            self.store.schedule_content(
                content_id=content_id,
                account_id=account_id,
                scheduled_for="2026-08-24T14:30-05:00",
            )
        self.store.approve_content(content_id)
        destination_id = self.store.schedule_content(
            content_id=content_id,
            account_id=account_id,
            scheduled_for="2026-08-24T14:30-05:00",
        )
        self.assertGreater(destination_id, 0)
        self.store.update_content(content_id, hook="A material edit")
        with self.assertRaisesRegex(ops.CreatorOpsError, "Approve"):
            self.store.schedule_content(
                content_id=content_id,
                account_id=account_id,
                scheduled_for="2026-08-25T14:30-05:00",
            )

    def test_default_publisher_is_dry_run_and_does_not_read_token(self) -> None:
        content_id = self._content()
        account_id = self._account()
        self.store.approve_content(content_id)
        self.store.schedule_content(
            content_id=content_id,
            account_id=account_id,
            scheduled_for="2020-01-01T00:00:00Z",
        )
        with patch.dict(os.environ, {"CREATOR_OPS_LIVE_PUBLISH": "0"}, clear=False):
            results = ops.OfficialPublisher(self.store).process_due()
        self.assertEqual(len(results), 1)
        self.assertFalse(results[0].live)
        self.assertIn("caption", results[0].payload)
        self.assertEqual(self.store.list_destinations()[0]["status"], "scheduled")

    def test_account_stores_only_credential_environment_name(self) -> None:
        secret = "this-is-a-token-value"
        with patch.dict(os.environ, {"TEST_PLATFORM_TOKEN": secret}, clear=False):
            self._account()
            row = self.store.list_accounts()[0]
        self.assertEqual(row["token_env"], "TEST_PLATFORM_TOKEN")
        database_bytes = Path(self.store.path).read_bytes()
        self.assertNotIn(secret.encode(), database_bytes)

    def test_local_brief_generation_is_schema_validated(self) -> None:
        topic = self.store.list_topics()[0]
        brief = ops.generate_brief(
            client=FakeOllamaClient(),  # type: ignore[arg-type]
            model="local-test-model",
            topic=topic,
            creator_goal="Teach a practical tradeoff.",
            requested_format="short video",
            creator_notes="Creator supplies the lived experience.",
            source_urls=("https://example.com/primary",),
        )
        self.assertEqual(brief.variant_a_hook, "Lead with the cost.")
        self.assertIn("platform rule", brief.evidence_needed[0])

    def test_live_failures_are_quarantined_and_do_not_block_later_items(self) -> None:
        account_id = self._account()
        for _index in range(2):
            content_id = self._content()
            self.store.approve_content(content_id)
            self.store.schedule_content(
                content_id=content_id,
                account_id=account_id,
                scheduled_for="2020-01-01T00:00:00Z",
            )
        with patch.dict(os.environ, {"TEST_PLATFORM_TOKEN": "secret"}, clear=False):
            results = FailingPublisher(self.store, live=True).process_due()
        self.assertEqual(len(results), 2)
        self.assertTrue(all(not result.success for result in results))
        self.assertEqual([row["status"] for row in self.store.list_destinations()], ["failed", "failed"])

    def test_experiment_insight_uses_latest_metric_per_destination(self) -> None:
        account_id = self._account()
        for variant, likes in (("A", 10), ("B", 20)):
            content_id = self._content(experiment="hook-test", variant=variant)
            self.store.approve_content(content_id)
            destination_id = self.store.schedule_content(
                content_id=content_id,
                account_id=account_id,
                scheduled_for="2026-08-24T14:30Z",
            )
            self.store.add_metric(destination_id, reach=100, likes=1)
            self.store.add_metric(destination_id, reach=100, likes=likes)
        insights = self.store.experiment_insights()
        self.assertEqual([item["variant_label"] for item in insights], ["A", "B"])
        self.assertAlmostEqual(insights[0]["engagement_rate"], 0.10)
        self.assertAlmostEqual(insights[1]["engagement_rate"], 0.20)

    def test_person_level_tracking_fields_are_absent(self) -> None:
        columns = {
            row["name"]
            for row in self.store.connection.execute("PRAGMA table_info(observations)")
        }
        self.assertFalse(columns & {"person_id", "profile_id", "username", "face_id"})
        self.assertTrue({"aggregate_sentiment", "source_rights"} <= columns)


if __name__ == "__main__":
    unittest.main()
