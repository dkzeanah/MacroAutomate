# ATLAS

spec 1.0 | 137 projects | 17 buckets | 327926 symbols | 4877091 lines | built 2026-10-27 08:25

This is tier 0. It is the only file you must always read.
Pick a bucket, then read that project's `INDEX.md`, then fetch slices by address. Do not open source files.

Address form: `@bucket/project:path.py#Symbol`

## Buckets

| bucket | projects | symbols | lines | covers |
|---|---:|---:|---:|---|
| `agent` | 26 | 10517 | 191382 | LLM harnesses, agent loops, providers, MCP, tool routers |
| `codetool` | 12 | 96323 | 1337589 | code analysis, indexing, refactoring, project management |
| `desktop-auto` | 13 | 3842 | 71232 | AutoHotkey, window/explorer automation, hotkeys, macros |
| `sim3d` | 24 | 108909 | 1695918 | 3D/graphics/geometry/CAD/ModernGL/dome and shell structures |
| `embedded` | 5 | 1213 | 19050 | ESP32, Arduino, firmware, device probes, serial |
| `vehicle` | 4 | 134 | 3641 | automotive, CAN bus, OBD, hybrid systems, avionics |
| `datatool` | 1 | 0 | 0 | file/drive analyzers, dedupe, search indexes, organization |
| `media` | 17 | 10897 | 237006 | audio/video/image processing, recording, transcoding |
| `docgen` | 5 | 1691 | 43803 | PDF, documents, printing, reports, publishing |
| `career` | 1 | 215 | 5230 | resume/ATS, job search automation, applications |
| `contentops` | 2 | 168 | 3297 | creator operations, social publishing, marketing pipelines |
| `osint` | 4 | 1219 | 27578 | research, intelligence gathering, investigation workbenches |
| `game` | 3 | 1137 | 23324 | games, bots, simulations of play |
| `datasci` | 5 | 1266 | 32573 | ML, notebooks, statistics, data visualization |
| `webapp` | 3 | 53 | 1410 | servers, APIs, FastAPI/Flask/frontends |
| `sysadmin` | 10 | 89854 | 1175480 | installers, packaging, environment setup, portable apps, backups |
| `electronics` | 2 | 488 | 8578 | circuits, schematics, EDA, electrical study material |

## Projects by bucket

### `agent` -- Agent & LLM Harness

- `@agent/sidelearner` p90 **HOT** (58f/8682L/559s) -- self-hosted agent harness: perception, memory twin, router, skills, tools
- `@agent/deepseek-harness` p87 **HOT** (25f/8718L/490s) -- manual override
- `@agent/a-llm-harness-custom` p83 **HOT** (170f/68031L/3916s) -- manual override
- `@agent/myllm` p77 (139f/38225L/2109s) -- manual override
- `@agent/multi_model_coding_workbench_v21` p62 (13f/2403L/156s) -- manual override
- `@agent/tri_model_coding_workbench` p62 (18f/3290L/230s) -- manual override
- `@agent/gui_desktop_agent_chat_findtext (1)` p57 (22f/9907L/301s) -- manual override
- `@agent/gui_desktop_agent_multiscale_vision` p57 (18f/3116L/200s) -- manual override
- `@agent/gui_desktop_agent_text_label_learning` p57 (16f/2306L/160s) -- manual override
- `@agent/guy_quest_app` p57 (10f/10788L/505s) -- manual override
- `@agent/ollama-preprompt` p55 (3f/1900L/92s) -- pre-prompt and pre-context builders for local models
- `@agent/chatgpt_tab_control_extension` p52 (0f/0L/0s) -- manual override
- `@agent/deepseek-workspace` p52 (0f/0L/0s) -- manual override
- `@agent/llm_extension_contract_system` p52 (5f/480L/33s) -- manual override
- `@agent/multi_model_coding_workbench` p52 (12f/2319L/155s) -- manual override
- `@agent/ollama_job_automation_studio` p52 (7f/2533L/131s) -- manual override
- `@agent/ollama_job_automation_studio_v1.1_responsive` p52 (7f/3012L/141s) -- manual override
- `@agent/ChatGPT - Library_files` p47 (0f/0L/0s) -- manual override
- `@agent/DSH_Trajectory_Lab` p47 (6f/2914L/159s) -- manual override
- `@agent/Kimi_Multimodal_Studio_v1.1.0` p47 (12f/6725L/312s) -- manual override
- `@agent/Local_SD15_Studio` p47 (8f/2309L/90s) -- manual override
- `@agent/Ollama_Code_Studio_v1.0.0` p47 (9f/3660L/192s) -- manual override
- `@agent/Ollama_Job_Automation_Studio_v1.2` p47 (12f/5230L/215s) -- manual override
- `@agent/gui_desktop_agent` p47 (12f/1580L/132s) -- manual override
- `@agent/gui_desktop_agent_fixed_region_selector` p47 (13f/1633L/132s) -- manual override
- `@agent/llm_extension_contract_system(1)` p47 (8f/1621L/107s) -- manual override

### `codetool` -- Code Tooling

- `@codetool/atlas` p95 **HOT** (24f/8850L/515s) -- the context map engine: scan, index, slice, gate, condense, fan-out
- `@codetool/harness-studio` p92 **HOT** (15f/5041L/295s) -- the unified Tk interface over every part of the system
- `@codetool/Consolidated_Python_Projects` p72 (3000f/1303516L/94310s) -- manual override
- `@codetool/Astrological` p60 (10f/2191L/171s) -- manual override
- `@codetool/code-analyzer` p60 (1f/811L/65s) -- the original AST analyzer this system grew out of
- `@codetool/python_code_analyzer_manager` p52 (1f/811L/65s) -- manual override
- `@codetool/python_code_analyzer_manager_tabfix` p52 (1f/828L/66s) -- manual override
- `@codetool/python_code_analyzer_manager_threadfix` p52 (1f/823L/65s) -- manual override
- `@codetool/celestial_virgo_relationship_suite` p47 (2f/3098L/166s) -- manual override
- `@codetool/celestial_virgo_relationship_suite (1)` p47 (2f/3098L/166s) -- manual override
- `@codetool/flax_trades_optimizer` p47 (9f/5768L/199s) -- manual override
- `@codetool/harness-tests` p40 (19f/2754L/240s) -- the test suite for sidelearner and atlas

### `desktop-auto` -- Desktop Automation

- `@desktop-auto/aAutomateMacro` p99 **HOT** (124f/24384L/1336s) -- manual override
- `@desktop-auto/AutoHotkey` p70 (0f/0L/0s) -- manual override
- `@desktop-auto/aAutomateMacro - Copy` p70 (16f/6360L/280s) -- manual override
- `@desktop-auto/aAutomateMacro_BACKUP_20260816-001845` p70 (16f/6360L/280s) -- manual override
- `@desktop-auto/amacroautomatest` p70 (32f/12720L/560s) -- manual override
- `@desktop-auto/Aahk_main` p62 (0f/0L/0s) -- manual override
- `@desktop-auto/Chrome_FindText_Automation_Demo_v1.1.0` p62 (11f/2852L/204s) -- manual override
- `@desktop-auto/gui_desktop_agent_chat_findtext` p57 (20f/3757L/228s) -- manual override
- `@desktop-auto/gui_desktop_agent_windows` p57 (38f/7506L/456s) -- manual override
- `@desktop-auto/Chrome_FindText_Automation_Demo` p52 (8f/1639L/140s) -- manual override
- `@desktop-auto/Chrome_FindText_Automation_Demo_v1.0.1` p52 (8f/1677L/141s) -- manual override
- `@desktop-auto/dev_kimi` p52 (0f/0L/0s) -- manual override
- `@desktop-auto/universal_media_transcript_database1` p47 (1f/3977L/217s) -- manual override

### `sim3d` -- 3D & Simulation

- `@sim3d/DomeSim` p98 **HOT** (609f/298561L/14042s) -- manual override
- `@sim3d/DomeSim-codex` p80 **HOT** (109f/66157L/2653s) -- manual override
- `@sim3d/CustomMenuFiles` p77 (3000f/1138351L/82822s) -- manual override
- `@sim3d/opencv` p70 (0f/0L/0s) -- manual override
- `@sim3d/bulk-dl` p65 (50f/74907L/4370s) -- manual override
- `@sim3d/BAIttleBots-claude-fix-tuple-import-error-011CUvWkJ2R9DT6gjWzy4RYx` p62 (19f/4304L/195s) -- manual override
- `@sim3d/BAIttleBots-claude-geodesic-dome-builder-011CUvNfrVy5yHP5zi69oFcL` p62 (19f/4304L/195s) -- manual override
- `@sim3d/BAIttleBots-claude-refactor-gc-menu-system-011CV5bswiNUaXK7xjz2KANt` p62 (28f/7893L/389s) -- manual override
- `@sim3d/acnc_training_suite_3d` p62 (21f/14395L/899s) -- manual override
- `@sim3d/amcrest_workshop_intelligence_console_v4_hardware_digitizer` p62 (8f/12796L/625s) -- manual override
- `@sim3d/dome` p62 (11f/14737L/361s) -- manual override
- `@sim3d/geodesic_raw_wedge_world_pinwheel` p60 (11f/2418L/136s) -- manual override
- `@sim3d/toyotahead` p57 (7f/5177L/180s) -- manual override
- `@sim3d/cnc_training_suite_3d_four_machine_v2_1` p52 (3f/3240L/212s) -- manual override
- `@sim3d/geodesic_raw_wedge_world` p52 (12f/3343L/173s) -- manual override
- `@sim3d/kimi-workspace` p52 (10f/4626L/112s) -- manual override
- `@sim3d/porch` p52 (1f/868L/62s) -- manual override
- `@sim3d/semicircle_beam_3d_compare` p52 (2f/931L/62s) -- manual override
- `@sim3d/straddle_chainsaw_mill` p52 (5f/1633L/46s) -- manual override
- `@sim3d/2007_Prius_ECB_ModernGL_3D_Lab` p47 (4f/1931L/100s) -- manual override
- `@sim3d/files` p47 (16f/25339L/751s) -- manual override
- `@sim3d/prius_sawmill_suite` p47 (6f/4160L/200s) -- manual override
- `@sim3d/prius_sawmill_suite_fixed` p47 (3f/2064L/100s) -- manual override
- `@sim3d/spherical_cnc_moderngl_digital_twin (1)` p47 (3f/3783L/224s) -- manual override

### `embedded` -- Embedded & Firmware

- `@embedded/esp32-sim` p57 (26f/11976L/763s) -- manual override
- `@embedded/EDM2.0-20260423T070919Z-3-001` p52 (0f/0L/0s) -- manual override
- `@embedded/arduino-canhacker-master` p52 (0f/0L/0s) -- manual override
- `@embedded/compsim` p52 (2f/4496L/332s) -- manual override
- `@embedded/Device_Firmware_Probe_Workbench` p47 (9f/2578L/118s) -- manual override

### `vehicle` -- Vehicle & Avionics

- `@vehicle/2007 Toyota Prius L4-1.5L  1NZ-FXE  Hybrid` p77 (0f/0L/0s) -- manual override
- `@vehicle/KS0411 keyestudio CAN-BUS Shield (Black and Eco-friendly)-` p57 (0f/0L/0s) -- manual override
- `@vehicle/prius-claude` p52 (3f/3641L/134s) -- manual override
- `@vehicle/savvycan_windows_20240619` p52 (0f/0L/0s) -- manual override

### `datatool` -- Data & Drive Tooling

- `@datatool/Everything-SDK-3.0.0.9` p47 (0f/0L/0s) -- manual override

### `media` -- Media Processing

- `@media/avideditor` p85 **HOT** (111f/43301L/2104s) -- manual override
- `@media/Doodly` p70 (54f/9871L/573s) -- manual override
- `@media/chinese` p70 (108f/31687L/1988s) -- manual override
- `@media/analyze` p65 (331f/40400L/561s) -- manual override
- `@media/aworkshop_cam` p62 (26f/7013L/506s) -- manual override
- `@media/universal_media_transcript_database_ffmpeg_fixed` p60 (9f/26363L/1125s) -- manual override
- `@media/Bookmarks&vid` p57 (35f/52645L/2675s) -- manual override
- `@media/wan2-2-fp8da-aoti-preview2` p57 (10f/997L/87s) -- manual override
- `@media/amcrest_direct_console` p52 (1f/2151L/143s) -- manual override
- `@media/python_findtext_certification_studio_v2` p52 (3f/8329L/358s) -- manual override
- `@media/python_findtext_certification_suite` p52 (2f/4204L/170s) -- manual override
- `@media/python_findtext_equivalent` p52 (1f/1329L/59s) -- manual override
- `@media/ESP32_Finger_Counter` p47 (1f/487L/23s) -- manual override
- `@media/Earbud_Automation_Studio` p47 (4f/236L/66s) -- manual override
- `@media/amcrest_direct_console_v1.1.0` p47 (1f/2281L/143s) -- manual override
- `@media/amcrest_direct_console_v1.2.0` p47 (1f/2757L/156s) -- manual override
- `@media/amcrest_direct_console_v1.2.1` p47 (1f/2955L/160s) -- manual override

### `docgen` -- Document Generation

- `@docgen/lifequest_book_system` p65 (22f/9829L/493s) -- manual override
- `@docgen/SmallEngineShop` p57 (41f/27699L/847s) -- manual override
- `@docgen/FlattenCodeboxesForPrint_ChromeExtension` p52 (0f/0L/0s) -- manual override
- `@docgen/Synergetics_Illustration_Flipbook` p47 (1f/1016L/68s) -- manual override
- `@docgen/book-codex` p47 (10f/5259L/283s) -- manual override

### `career` -- Career & Job Search

- `@career/ojas` p70 (12f/5230L/215s) -- job automation studio: resume/ATS scoring, RAG, visual synthesis

### `contentops` -- Creator Operations

- `@contentops/creator-ops` p75 (6f/2389L/122s) -- content pipeline: briefs, drafts, review queue, metrics
- `@contentops/puagpt` p57 (1f/908L/46s) -- manual override

### `osint` -- OSINT & Research

- `@osint/Evergreen_OSINT_Workbench_v1.0.0` p62 (18f/4660L/234s) -- manual override
- `@osint/amcrest_workshop_intelligence_console_v4_0_1_hog_fix` p52 (4f/8730L/370s) -- manual override
- `@osint/amcrest_workshop_intelligence_console_v5_same_gui` p52 (4f/8748L/374s) -- manual override
- `@osint/amcrest_workshop_intelligence_console_v3` p47 (3f/5440L/241s) -- manual override

### `game` -- Games & Bots

- `@game/Book` p73 (71f/22200L/1078s) -- manual override
- `@game/six_point_env` p57 (0f/0L/0s) -- manual override
- `@game/snowball` p55 (2f/1124L/59s) -- manual override

### `datasci` -- Data Science

- `@datasci/OmniVoice-0.1.5` p57 (45f/13782L/365s) -- manual override
- `@datasci/pythonProjects` p57 (8f/9499L/471s) -- manual override
- `@datasci/tentacle_robot_blueprint_v2` p52 (2f/3424L/142s) -- manual override
- `@datasci/pua` p47 (5f/4161L/183s) -- manual override
- `@datasci/spherical_cnc_digital_twin` p47 (2f/1707L/105s) -- manual override

### `webapp` -- Web Applications

- `@webapp/TGE` p65 (1f/252L/3s) -- manual override
- `@webapp/guy_quest_app_port5050` p57 (2f/1158L/50s) -- manual override
- `@webapp/CameraWebServer` p52 (0f/0L/0s) -- manual override

### `sysadmin` -- System & Packaging

- `@sysadmin/TheGrandExchange` p75 (1f/252L/3s) -- manual override
- `@sysadmin/Projs` p73 (2635f/1005824L/78511s) -- manual override
- `@sysadmin/ObjectDigitizerWorkbench_source_bundle` p65 (81f/2493L/222s) -- manual override
- `@sysadmin/ocr` p65 (87f/7379L/568s) -- manual override
- `@sysadmin/guy_quest_runescape_1000` p57 (2f/1819L/66s) -- manual override
- `@sysadmin/Kimi_Multimodal_Studio_v1.0.0` p52 (11f/4927L/254s) -- manual override
- `@sysadmin/omnivoice_env` p52 (0f/0L/0s) -- manual override
- `@sysadmin/((user))` p47 (8f/992L/87s) -- manual override
- `@sysadmin/(portable - Apps)` p47 (556f/149463L/10053s) -- manual override
- `@sysadmin/Local_SD15_Studio_v1.0.1_FIXED` p47 (8f/2331L/90s) -- manual override

### `electronics` -- Electronics

- `@electronics/circuit_study_guide_builder_bundle_fixed` p52 (1f/3084L/166s) -- manual override
- `@electronics/AVIONICS` p47 (9f/5494L/322s) -- manual override

## Resolution order for vague requests

When a request does not name a project, resolve it against pinned and high-priority projects in the most relevant bucket before generating anything new. Existing capability beats new code.

1. `@desktop-auto/aAutomateMacro` (p99, 1336 symbols) -- manual override
1. `@sim3d/DomeSim` (p98, 14042 symbols) -- manual override
1. `@codetool/atlas` (p95, 515 symbols) -- the context map engine: scan, index, slice, gate, condense, fan-out
1. `@codetool/harness-studio` (p92, 295 symbols) -- the unified Tk interface over every part of the system
1. `@agent/sidelearner` (p90, 559 symbols) -- self-hosted agent harness: perception, memory twin, router, skills, tools
1. `@agent/deepseek-harness` (p87, 490 symbols) -- manual override
1. `@media/avideditor` (p85, 2104 symbols) -- manual override
1. `@agent/a-llm-harness-custom` (p83, 3916 symbols) -- manual override

Workspace root: `C:\Users\Don\Desktop\aAutomateMacro\fan\harness`