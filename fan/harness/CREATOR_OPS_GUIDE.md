# Creator Operations deployment and usage guide

This companion application turns the local Ollama-to-DeepSeek workflow into a creator-owned planning, approval, scheduling, publishing, experiment, and metrics system. It changes files inside the DeepSeek Harness repository but does not replace or patch the Harness Web interface: launch `Creator_Ops_GUI.bat` for this dashboard and `Ollama_DeepSeek_GUI.bat` for the general prompt orchestrator.

The application uses local Ollama models for routine brief creation. DeepSeek review is optional, explicit, and confirmed before any paid request. The creator supplies and approves all media and final copy. SQLite records plans and aggregate outcomes; access tokens remain in environment variables.

## 1. Prerequisites

- Windows 10 or 11 with Python 3.11 or newer from [python.org](https://www.python.org/downloads/windows/). Enable **Add Python to PATH** and include Tcl/Tk during installation.
- [Ollama](https://ollama.com/download/windows) running locally with at least one text model installed.
- `deepseek-harness-sdk` only when paid DeepSeek review is wanted. Use the **Install / update Harness SDK** button in the existing Ollama/DeepSeek GUI; local creator operations do not need the SDK.
- Official developer applications and permissions for every platform that will receive live posts.
- Creator-owned media hosted at a public HTTPS URL when Instagram or TikTok needs the platform to fetch it.

No command-line parameters are required. Double-click the launchers and configure work inside the GUI or Windows environment settings.

## 2. First launch

1. Double-click `Creator_Ops_GUI.bat` in `examples/jsonrpc-agent`.
2. Open **Content Studio**, click **Find models**, and select an installed Ollama text model.
3. Open **Dashboard & Topics** to review the ten seeded topic lanes. They are inferred from the interests supplied with the request; the application cannot read private ChatGPT conversation history.
4. Choose a topic, enter the audience goal, add primary-source URLs, and add the creator's own experience or angle.
5. Click **Generate local brief**. Ollama returns an editable JSON brief with an honest tension, opposing view, evidence checklist, talking points, and two hook variants.
6. Edit the brief, verify every factual claim outside the model, and click **Save draft**.
7. Supply creator-owned media and complete the final platform copy. The suite does not create synthetic creator media.
8. Click **Human approve current draft** only after reviewing sources, claims, media rights, audience framing, and platform policy.

The database is created at `%LOCALAPPDATA%\DeepSeekHarnessCreatorOps\creator_ops.db`. Use **Setup & Guide → Open data folder** to reach it. Back up this file to preserve plans, schedules, experiments, and aggregate metrics.

## 3. Optional DeepSeek review

Enter a DeepSeek API key in **Content Studio** or set `DEEPSEEK_API_KEY` before launching the GUI. The entry is held only in the running process and is not saved to SQLite. Click **DeepSeek review (paid)** to send the current Ollama-prepared brief and source URL list to DeepSeek Harness after a cost confirmation.

The paid review asks for factual-risk, sourcing, fairness, and platform-policy checks. It does not publish or generate media. Treat its response as editorial assistance, not evidence. Paste verified improvements into the editable brief and save again; every edit clears the earlier approval.

## 4. Add platform accounts

Open **Queue & Accounts** and add one row per official API identity. The **Platform account ID** is the Page, Instagram professional account, or TikTok account identifier expected by that platform. **Token env name** is the name of an environment variable, not the token itself.

Suggested environment-variable names are `FACEBOOK_PAGE_ACCESS_TOKEN`, `INSTAGRAM_ACCESS_TOKEN`, and `TIKTOK_ACCESS_TOKEN`. Create them in Windows **System Properties → Advanced → Environment Variables**, then restart the GUI so the new process can read them. Never paste access-token values into the display name, account ID, creator notes, sources, or database.

### Facebook Pages

The adapter writes to the Meta Graph API Page `/feed` endpoint for text/link posts and `/photos` for creator-owned public images. It does not automate Facebook personal profiles or the browser interface. Create a Meta app, obtain the current Page publishing permissions through Meta's review process, authorize the Page, and store the Page access token in the configured environment variable.

Set `META_GRAPH_VERSION` when the deployment needs a Graph version different from the application's default, and optionally set `META_GRAPH_BASE_URL` for an approved compatible endpoint. Confirm the current version and permissions in Meta's developer documentation before enabling live mode.

### Instagram professional accounts

Instagram publishing uses Meta's official container flow: create a media container and then call `media_publish`. The account must be an eligible professional account connected through the selected Instagram Login or Facebook Login flow, the application needs the documented publishing permissions, and the image must be available at a public URL that Meta can fetch. See Meta's [official Instagram API workspace](https://www.postman.com/meta/instagram/documentation/6yqw8pt/instagram-api).

### TikTok

TikTok publishing uses the official Content Posting API photo Direct Post endpoint. Register an application, add the Content Posting API product, receive approval for the required scope, authorize the user, and verify the domain hosting pull-from-URL media. TikTok documents the setup in its [Direct Post guide](https://developers.tiktok.com/doc/content-posting-api-get-started/) and [Content Posting API overview](https://developers.tiktok.com/products/content-posting-api/).

`TIKTOK_PRIVACY_LEVEL` defaults to `SELF_ONLY`. Keep that default while validating a deployment. TikTok restricts unaudited clients, including visibility limits; pass the platform's audit before expecting public automated publishing.

## 5. Schedule and preview

1. Select an approved content item and an enabled account.
2. Enter an ISO 8601 local time, such as `2026-08-24T14:30-05:00`.
3. Click **Schedule**. The database stores the time in UTC.
4. When it is due, click **Preview due**. The preview shows the exact account, caption, media URL, sources, and experiment labels without making a network write or removing the item from the queue.
5. Correct the draft if needed, approve it again, and preview again.

Dry-run is the permanent safe default. A database entry, API token, or schedule alone cannot publish.

## 6. Enable live publishing

Enable live mode only after each platform's sandbox/private test succeeds. Set `CREATOR_OPS_LIVE_PUBLISH=1` in the environment that starts the GUI or scheduled worker, then restart that process. The GUI still asks for confirmation before **Publish due now**. A live worker requires all of these conditions:

- the content carries a current human approval;
- its destination is due and still scheduled;
- the account is enabled;
- `CREATOR_OPS_LIVE_PUBLISH` equals `1`;
- the account's named token environment variable exists; and
- the official API accepts the account, permissions, media, and payload.

A live request first claims its destination as `publishing`; a successful response stores the remote post ID. A failed or timed-out request stores the error and marks that destination failed so an unattended worker does not blindly retry. A timeout can mean the platform accepted the post but its response was lost, so inspect the official account before creating a corrected, approved schedule.

## 7. Windows Task Scheduler

Use Task Scheduler only after manual dry-run and private/sandbox validation.

1. Open **Task Scheduler → Create Task** and run it as the Windows user who owns the database and environment variables.
2. Add a trigger at the desired queue-check interval, such as every 15 minutes, and set **If the task is already running** to **Do not start a new instance**.
3. Add an action that starts `Creator_Ops_Worker.bat`; leave **Add arguments** empty and set **Start in** to the full `examples\jsonrpc-agent` directory.
4. Start with `CREATOR_OPS_LIVE_PUBLISH` absent. Run the task manually and inspect its JSON output in Task Scheduler history or an operator-controlled log.
5. After official API validation, set `CREATOR_OPS_LIVE_PUBLISH=1` for that user and restart the scheduled task process.

The worker takes no CLI parameters and reads the same per-user database as the GUI. In dry-run mode it leaves due items scheduled, so repeated checks remain non-mutating. In live mode it publishes each due item once unless the platform returns an error before a remote ID is recorded.

## 8. A/B testing and learning

Give related drafts the same **Experiment** value and different **Variant** values such as `A` and `B`. Keep the thesis, offer, audience, platform, media class, and distribution window as similar as practical; change one hook or framing decision. Schedule both through comparable accounts or time windows.

After platform analytics settle, choose the destination under **Metrics & Experiments** and enter aggregate reach, views, interactions, clicks, follower change, and revenue. The insight table uses the latest observation per destination and calculates engagement rate as interactions divided by reach, falling back to views when reach is unavailable. It reports evidence; it does not claim causation or automatically rewrite future content.

Do not store names, profile IDs, faces, or dossiers on commenters. For authorized OCR or manual imports, retain aggregate themes, recurring questions, and broad sentiment only, with the source and usage rights documented outside personal data.

## 9. Topic and controversy policy

The seeded lanes cover veteran transition, Navy readiness, local politics, relationships, transparent entrepreneurship, repair culture, AI and authorship, computer-vision privacy, platform dependence, and automation's effect on work. Their controversy comes from a real tradeoff between defensible positions. Each brief must give the audience practical value and represent the strongest opposing view fairly.

The suite deliberately excludes invented Reddit-style stories, intentionally false claims, impersonation, outrage bait, engagement rings, covert screen automation, personal-profile automation, and identity-level sentiment tracking. Besides being harmful to audience trust, Meta says it reduces reach and monetization for spammy content and fake engagement, while rewarding original creator work: [spam enforcement](https://about.fb.com/news/2025/04/cracking-down-spammy-content-facebook/) and [original-content guidance](https://about.fb.com/news/2026/03/rewarding-original-creators-on-facebook/).

## 10. Monetization expectations

Do not treat follower-price formulas, guaranteed invitation thresholds, page-count claims, or individual revenue screenshots as platform rules. They are marketing claims unless the platform's current official documentation verifies them. Meta describes Facebook Content Monetization as performance-based and spanning eligible Reels, longer videos, photos, and text posts; its March 2026 update says access remains invitation-based with an interest form in Professional Dashboard: [program introduction](https://about.fb.com/news/2024/10/monetize-content-facebooks-new-streamlined-program/) and [2026 creator update](https://about.fb.com/news/2026/03/creator-fast-track-grow-your-audience-earn-money-on-facebook/).

Build decisions around qualified views, originality, audience retention, useful engagement, policy compliance, and owned records. Re-check official platform guidance before spending money or changing a production publishing workflow.

## 11. Recovery and updates

Back up `creator_ops.db` before replacing the application files. Secrets do not travel with that backup and must be configured separately on the destination machine. Pull repository updates only with a clean understanding of local uncommitted files; this suite is an extension under `examples/jsonrpc-agent`, not a patch to the Harness Web preset.

Use `Ollama_DeepSeek_GUI.bat` for general local-preprompt orchestration and `Creator_Ops_GUI.bat` for content operations. Both import `ollama_preprompt.py`, so Ollama discovery, structured local calls, and explicit DeepSeek SDK handoffs share one implementation.
