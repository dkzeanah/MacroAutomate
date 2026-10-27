"""One typed tool contract shared by the gateway, API agent, and MCP server."""
from __future__ import annotations

from typing import Annotated, Any, Literal
from pydantic import BaseModel, ConfigDict, Field, AliasChoices, field_validator, model_validator
import re


class Arguments(BaseModel):
    model_config = ConfigDict(extra='forbid')


class Empty(Arguments):
    pass


class Activate(Arguments):
    title: str = Field(min_length=1, max_length=300)


class TypeText(Arguments):
    text: str = Field(min_length=1, max_length=8000)
    hwnd: int = Field(default=0,ge=0)


class SendKey(Arguments):
    keys: str = Field(min_length=1, max_length=80)
    hwnd: int = Field(default=0,ge=0)


class Point(Arguments):
    x: int = Field(ge=-20000, le=20000)
    y: int = Field(ge=-20000, le=20000)
    hwnd: int = Field(default=0,ge=0)


class Named(Arguments):
    name: str = Field(min_length=1, max_length=120)


class ContextFind(Arguments):
    query: str = Field(min_length=1, max_length=1000)


class ContextGet(Arguments):
    address: str = Field(min_length=5, max_length=500)


class LearningClaim(Arguments):
    claim_id: int = Field(ge=1)


class LearningLesson(Arguments):
    query: str = Field(default='', max_length=1000)
    claim_id: int = Field(default=0, ge=0)


class ScriptWrite(Named):
    source: str = Field(min_length=1, max_length=131072)
    overwrite: bool = False
    description: str = Field(default='', max_length=2000)
    tags: list[str] = Field(default_factory=list, max_length=20)
    usage: str = Field(default='', max_length=4000)
    examples: list[str] = Field(default_factory=list, max_length=12)
    input_schema: dict[str, Any] = Field(default_factory=dict)


class ScriptRun(Named):
    timeout_seconds: int = Field(default=60, ge=1, le=300)
    wait: bool = False
    inputs: dict[str, Any] = Field(default_factory=dict)


class RunID(Arguments):
    run_id: str = Field(min_length=1, max_length=80)


class Search(Arguments):
    query: str = Field(default='', max_length=1000)
    limit: int = Field(default=20, ge=1, le=50)


class CatalogUpdate(Named):
    description: str = Field(default='', max_length=2000)
    tags: list[str] = Field(default_factory=list, max_length=20)
    usage: str = Field(default='', max_length=4000)
    examples: list[str] = Field(default_factory=list, max_length=12)


class Revision(Named):
    revision: int = Field(default=0, ge=0)


class KnowledgeStore(Named):
    content: str = Field(min_length=1, max_length=20000)
    description: str = Field(default='', max_length=2000)
    tags: list[str] = Field(default_factory=list, max_length=20)
    source: str = Field(default='', max_length=1000)


class Region(Arguments):
    x: int = Field(ge=-20000, le=20000)
    y: int = Field(ge=-20000, le=20000)
    w: int = Field(ge=1, le=8192)
    h: int = Field(ge=1, le=8192)

    @model_validator(mode='after')
    def bounded_capture(self):
        if self.w * self.h > 12000000:
            raise ValueError('Use a crop smaller than 12 million pixels')
        return self


class Window(Arguments):
    hwnd: int = Field(default=0, ge=0)


class WindowLearn(Window):
    refresh: bool = False
    maximize: bool = False
    fullscreen: bool = False
    activate_menu: bool = False
    explore_menus: bool = False
    probe_navigation: bool = False


class MenuProbe(Window):
    hwnd: int = Field(ge=1)
    action: Literal['catalog', 'open', 'submenu', 'return'] = 'catalog'
    label: str = Field(default='', max_length=300)
    all_menus: bool = False
    context_path: str = Field(default='', max_length=800)


class ItemProbe(Window):
    hwnd: int = Field(ge=1)
    path: str = Field(min_length=1, max_length=600)
    label: str = Field(min_length=1, max_length=300)


class Explore(Window):
    hwnd: int = Field(ge=1)
    menus: bool = True
    controls: bool = True
    max_branches: int = Field(default=8, ge=1, le=30)
    max_depth: int = Field(default=2, ge=1, le=4)


class ChainStatus(Arguments):
    after: int = Field(default=0, ge=0)
    limit: int = Field(default=100, ge=1, le=500)


class UnitStep(Arguments):
    id: str = Field(default='',max_length=100)
    tool: str = Field(min_length=1,max_length=100)
    arguments: dict[str, Any] = Field(default_factory=dict,validation_alias=AliasChoices('arguments','inputs'),
        description='Child tool arguments, including any nested ScriptRun inputs. Whole values may use {$input:"field"} or {$result:"step.field"}.')
    expect: dict[str, Any] = Field(default_factory=dict,
        description='Result path to exact expected value, or an operator object such as {"stdout":{"contains":"NAV_VERIFIED:label"}}. Use marker contains checks rather than escaped newlines.')
    branch: str = Field(default='',max_length=300)
    note: str = Field(default='',max_length=1000)


class UnitSave(Named):
    steps: list[UnitStep] = Field(min_length=1, max_length=100)
    input_schema: dict[str, Any] = Field(default_factory=dict)
    description: str = Field(default='', max_length=2000)
    overwrite: bool = False


class UnitRun(Named):
    inputs: dict[str, Any] = Field(default_factory=dict)
    timeout_seconds: int = Field(default=600, ge=1, le=3600)


class TourCue(Arguments):
    text: str = Field(min_length=1, max_length=2000)
    seconds: int = Field(default=4, ge=0, le=30)
    wait_for_continue: bool = False
    timeout_seconds: int = Field(default=300, ge=1, le=600)


class TraceStep(Arguments):
    label: str = Field(min_length=1, max_length=300)
    phase: Literal['before', 'after', 'return', 'uncertain'] = 'before'
    hwnd: int = Field(default=0, ge=0)
    x: int | None = Field(default=None, ge=-30000, le=30000)
    y: int | None = Field(default=None, ge=-30000, le=30000)
    evidence: str = Field(default='', max_length=2000)


class WindowKnowledge(Arguments):
    window_id: str = Field(default='', max_length=80)
    query: str = Field(default='', max_length=500)
    offset: int = Field(default=0, ge=0)
    limit: int = Field(default=40, ge=1, le=100)


class WindowShortcut(Arguments):
    hwnd: int = Field(ge=1)
    shortcut: Literal['address_bar','address_bar_ctrl','search','next_tab','previous_tab','menu_bar','command_palette','quick_open','tab_1','tab_2','tab_3','tab_4','tab_5','tab_6','tab_7','tab_8','tab_9']


class RegionWindow(Window):
    region: Region | None = None


class Inspect(RegionWindow):
    include_image: bool = True
    grid: bool = True
    include_ocr: bool = True
    limit: int = Field(default=200, ge=1, le=500)
    lang: str = Field(default='', max_length=100)


class OCR(RegionWindow):
    include_image: bool = False
    grid: bool = True
    lang: str = Field(default='', max_length=100)


class PageLearn(Window):
    refresh: bool = False
    max_elements: int = Field(default=1000, ge=1, le=1500)
    max_patterns: int = Field(default=40, ge=0, le=100)
    lang: str = Field(default='', max_length=100)


class PageGet(Arguments):
    page_id: str = Field(min_length=1, max_length=100)
    query: str = Field(default='', max_length=1000)
    group: str = Field(default='', max_length=200)
    offset: int = Field(default=0, ge=0)
    limit: int = Field(default=30, ge=1, le=100)


class PageElement(Window):
    page_id: str = Field(min_length=1, max_length=100)
    element_id: str = Field(min_length=1, max_length=100)


class PageImage(Arguments):
    page_id: str = Field(min_length=1, max_length=100)
    element_id: str = Field(default='', max_length=100)


class JobConfiguration(Arguments):
    sites: list[str] = Field(min_length=1, max_length=5)
    roles: list[str] = Field(min_length=1, max_length=20)
    locations: list[str] = Field(default_factory=list, max_length=20)
    remote: Literal['any', 'remote', 'hybrid', 'onsite'] = 'any'
    remote_preferred: bool = False
    submission_mode: Literal['review', 'submit_completed'] = 'review'
    minimum_salary: int = Field(default=0, ge=0)
    resume_path: str = Field(default='', max_length=1000)
    profile: dict[str, str] = Field(default_factory=dict)
    answers: dict[str, str | bool] = Field(default_factory=dict)
    browser_execution: bool = False
    automatic_discovery: bool = False
    browser_mode: Literal['existing_chrome'] = 'existing_chrome'


class JobCandidate(Arguments):
    url: str = Field(min_length=1, max_length=4000)
    title: str = Field(default='', max_length=1000)
    company: str = Field(default='', max_length=1000)
    location: str = Field(default='', max_length=1000)
    remote: bool | None = None
    country: str = Field(default='', max_length=100)
    annual_salary_min: int | None = Field(default=None, ge=0)
    annual_salary_max: int | None = Field(default=None, ge=0)
    evidence_url: str = Field(default='', max_length=4000)


class JobDiscovery(Arguments):
    page_id: str = Field(min_length=1, max_length=100)


class JobSharing(Arguments):
    enabled: bool


class JobStart(Arguments):
    hours: float = Field(default=8, ge=.25, le=24)


class JobControl(Arguments):
    run_id: str = Field(min_length=1, max_length=80)
    action: Literal['pause', 'resume', 'stop']


class PatternList(Arguments):
    query: str = Field(default='', max_length=1000)
    limit: int = Field(default=100, ge=1, le=500)


class WorkflowList(Arguments):
    query: str = Field(default='', max_length=1000)


class PatternSearch(RegionWindow):
    name: str = Field(default='', max_length=120)
    text: str = Field(default='', max_length=131072)
    err1: float = Field(default=0, ge=0, le=0.5)
    err0: float = Field(default=0, ge=0, le=0.5)
    limit: int = Field(default=20, ge=1, le=100)

    @model_validator(mode='after')
    def named_or_explicit_pattern(self):
        if not self.name and not self.text:
            raise ValueError('Supply a saved pattern name or explicit FindText text')
        if not self.name and '$' not in self.text:
            raise ValueError('Explicit FindText text must contain its $ bitmap separator')
        return self


class PatternCapture(Window):
    region: Region
    name: str = Field(min_length=1, max_length=120, pattern=r'^[^<>|\x00-\x1f]+$')
    description: str = Field(default='', max_length=2000)
    qualifier: str = Field(default='', max_length=2000)
    overwrite: bool = False
    threshold: Annotated[int, Field(ge=0, le=255)] | Annotated[str, Field(pattern=r'^\*{1,2}\d{1,3}$')] = Field(
        default='**50', description="0..255 or '*128' grayscale / '**50' gray difference; default '**50'")

    @field_validator('threshold')
    @classmethod
    def supported_threshold(cls, value):
        if isinstance(value, int) and 0 <= value <= 255:
            return value
        if isinstance(value, str) and re.fullmatch(r'\*{1,2}\d{1,3}', value) and int(value.lstrip('*')) <= 255:
            return value
        raise ValueError("threshold must be 0..255, '*128' or '**50'")

    @model_validator(mode='after')
    def explicit_element_crop(self):
        if not self.name.strip():
            raise ValueError('Pattern name must not be blank')
        if not 3 <= self.region.w <= 1024 or not 3 <= self.region.h <= 1024:
            raise ValueError('Pattern capture width/height must be 3..1024 pixels')
        return self


class WorkflowSave(Named):
    steps: list[dict[str, Any]] = Field(min_length=1, max_length=300)
    description: str = Field(default='', max_length=2000)
    overwrite: bool = False


class WorkflowRun(Named):
    timeout_seconds: int = Field(default=120, ge=1, le=300)


class InputSettings(Arguments):
    settings: dict[str, Any]


class LibraryRead(Arguments):
    path: str = Field(min_length=1, max_length=500)
    start_line: int = Field(default=1, ge=1)
    line_count: int = Field(default=120, ge=1, le=200)


# Descriptions describe actual implementations; optional parameters remain optional.
TOOLS: dict[str, tuple[type[Arguments], str]] = {
    'fan_window_learn': (WindowLearn, 'Preferred standard window discovery: cheap live identity/schema/tab probe, then 75% use a matching saved map / 25% random fresh OCR/image/control/menu survey. Changed/new/aged contexts force fresh. maximize/activate_menu temporarily explore a foreground target and restore its layout; fullscreen supports Explorer only. Saved geometry is historical. Returns provenance and estimated text-token savings, not a billing measurement.'),
    'fan_window_knowledge': (WindowKnowledge, 'Search or paginate indexed window facts: controls, named sections, nine geometric zones, tabs/active states, menus, observed/documented shortcuts and their parent/zone relationships. Facts are historical evidence; resolve live before input.'),
    'fan_window_probe': (Window, 'Cheap live accessibility/schema/tab and native menu probe without OCR, images or model calls. Bounded traversal is not complete interface coverage.'),
    'fan_window_survey': (WindowLearn, 'Native bounded deep control/OCR/image/menu survey. Prefer fan_window_learn to apply the 75/25 policy. Optional foreground-only maximize, ALT menu hints and Explorer F11 exploration restore the previous layout; menu commands are never invoked.'),
    'fan_window_shortcut': (WindowShortcut, 'Use an app-scoped documented navigation shortcut in an exact foreground window, with visible native targeting and post-observation. Explorer supports address_bar (!d), search, tabs and menu focus; VS Code supports command_palette/quick_open. verified=false means effect is uncertain; do not automatically repeat input.'),
    'fan_project_paths': (Search, 'Find indexed Desktop project/folder/file paths without copying source. Indexing is incremental metadata only and excludes dependency/cache trees and reparse-point traversal. Verify a path before using it; use Atlas for indexed code content.'),
    'window_list': (Empty, 'List visible titled desktop windows with handles.'),
    'window_active': (Empty, 'Read the foreground Windows window handle and title.'),
    'window_activate': (Activate, 'Activate an existing window by title substring. Inspect windows first.'),
    'fan_window_prepare': (Window, 'Activate and verify the assigned HWND/process immediately before a routed action; returns its identity. Explicit HWND required for an unbound task.'),
    'text_type': (TypeText, 'Type Unicode text into the active window.'),
    'key_send': (SendKey, 'Send AutoHotkey v2 key syntax to the active window.'),
    'mouse_move': (Point, 'Move to absolute screen x/y, including negative coordinates on secondary monitors.'),
    'mouse_click': (Point, 'Left click absolute screen x/y after locating the target from current observations.'),
    'ahk_script_list': (Empty, 'List agent-created AHK v2 scripts and their indexed metadata.'),
    'ahk_script_write': (ScriptWrite, 'Create/edit a complete AHK v2 tool starting #Requires AutoHotkey v2.0. Saves descriptions, tags, usage, examples, input_schema (JSON Schema object) and source revisions. Parameterized scripts decode FAN_TOOL_INPUT using FanBridgeJsonDecode after including FanBridgeClient.ahk. Read real library APIs before including them.'),
    'ahk_script_read': (Named, 'Read a saved AHK v2 script and its indexed metadata before correcting it.'),
    'ahk_script_validate': (Named, 'Validate a saved script using the installed AutoHotkey v2 /validate parser without executing it. Syntax validity is stored against the exact source hash and reused on later identical validation requests; it does not prove UI effects.'),
    'ahk_script_run': (ScriptRun, 'Execute a saved script using installed AutoHotkey v2. inputs is JSON validated against its saved input_schema and passed through FAN_TOOL_INPUT. Default wait=false returns a managed run_id and leaves GUI scripts running until dismissed/cancelled. wait=true waits up to timeout_seconds then stops that process. Inspect actual UI/output before claiming the effect.'),
    'ahk_script_status': (RunID, 'Read the actual process state, exit code, stdout and stderr of an agent-created script run.'),
    'ahk_script_cancel': (RunID, 'Stop only the managed script process identified by run_id.'),
    'tool_catalog_list': (Search, 'List indexed saved scripts, patterns, workflows and learned knowledge with descriptions and usage.'),
    'tool_catalog_search': (Search, 'Search persistent names, tags, descriptions, usage and content to reuse previously learned tools.'),
    'tool_catalog_get': (Named, 'Read one indexed saved tool or knowledge record, its provenance and revision.'),
    'tool_catalog_update': (CatalogUpdate, 'Edit the indexed description, tags, usage and examples for an existing saved tool.'),
    'tool_catalog_revisions': (Revision, 'List saved source revisions, or retrieve one revision. revision=0 lists revisions; it does not execute code.'),
    'knowledge_store': (KnowledgeStore, 'Save a reusable note or model inference. These notes are explicitly labelled inference; direct tool observations are stored separately.'),
    'knowledge_search': (Search, 'Search persistent observed evidence, source references and model inferences. Verify old coordinates against the current window.'),
    'automation_knowledge_search': (Search, 'Read empirical pre/post-tool procedure memory: exact artifact revision, executions, failures, syntax/UI verification evidence and contexts. Reuse existing scripts/workflows; no arbitrary model claim is promoted to a fact.'),
    'context_map_find': (ContextFind, 'Query the existing local Atlas context map to locate reusable code before authoring it. Returns stable symbol addresses and reuse/placement suggestions. A MISS applies only to indexed scope and supported languages.'),
    'context_map_get': (ContextGet, 'Fetch an exact source slice and its caller/callee edges through Atlas using an address returned by context_map_find. Checks indexed source freshness; never reads an arbitrary supplied filesystem path.'),
    'fan_code_index': (ContextFind, 'Launch the separate Python Atlas application under fan/harness, optionally searching indexed symbols. Does not embed Atlas into the AHK GUI. Local process launch; zero model calls.'),
    'fan_capabilities': (Empty, 'Discover the live Fan workflow action catalog, library names, current configuration and concrete API signatures.'),
    'fan_taskbar_learn': (Empty, 'Passively learn visible taskbar icons: observed accessibility labels, pinned-shortcut program identity, screenshots and binary FindText patterns. Does not switch apps or press Windows hotkeys. Saves knowledge locally; hidden and unlabelled controls remain unknown.'),
    'fan_learning_lesson': (LearningLesson, 'Show a lesson for an exact claim_id or query. Explains actual retained evidence and uncertainty without controlling underlying applications.'),
    'fan_learning_compile': (LearningClaim, 'Compile a recorded multi-step Usage sequences claim into a saved native workflow for isolated rehearsal. Retains source evidence and exact tokens. No model calls; does not certify or operate the original application.'),
    'fan_learning_rehearse': (Named, 'Reuse an already saved learned rehearsal by name. Executes its existing native workflow only in a local fixture, with per-step order checks and no input to underlying applications. No model calls, recompilation or new source generation.'),
    'fan_taskbar_list': (Search, 'Read learned taskbar targets, program metadata, stored photo references, binary-pattern coverage and verification counts. These are historical observations; use fan_taskbar_open for live resolution.'),
    'fan_taskbar_open': (Named, 'Open/activate a learned application by its taskbar label. Re-resolve current accessible name and unique FindText match, show a yellow pre-action target box, click that icon, and verify the foreground executable. Never launches a guessed executable or uses a remembered screen coordinate. If action_performed=true but verified=false, do not automatically repeat the click.'),
    'fan_learning_insights': (Search, 'Read compact consolidated learning metrics, evidence coverage and improvement candidates from Settings analysis. query filters relevant findings; verify observed support, freshness and live targets before applying a recommendation.'),
    'fan_discovered_targets': (Search, 'Read automatically captured accessibility targets, names, roles, shortcuts, window-relative bounds, locator paths and workflow/Claude/ChatGPT/development topics. These are observations; resolve and verify the live control before acting.'),
    'fan_window_inspect': (Inspect, 'Examine hwnd (0 means the last activated Chrome base/current target) using Fan UI inspection, observed control bounds, screenshot and optional numbered grid. region={x,y,w,h} can crop the target; limit bounds the control catalog, include_ocr and include_image select evidence. Image evidence is automatically routed to the vision model.'),
    'fan_page_learn': (PageLearn, 'Learn/reuse a visible Chrome webpage without input: retained screenshot, MSAA controls/links/hierarchy, OCR, screen snips, FindText candidates and a searchable page_id. Default checks URL and form/dialog schema and reuses memory without another capture. refresh=true captures new visible content. Images/bounds are historical; resolve live before input. Remote access requires saved user approval for this job-site origin and api.deepseek.com; the gateway enforces both.'),
    'fan_page_probe': (Window, 'Read current Chrome URL, visible accessibility controls and form/dialog schema without OCR, screen snips or pattern extraction. Used for retained-map lookup and live validation.'),
    'fan_page_get': (PageGet, 'Search/paginate a saved page atlas by query or exact group. Returns observed element bounds, link targets when exposed, crop photo refs, OCR associations, locator paths, FindText patterns and inferred action/group descriptions. Saved coordinates are historical; fan_page_resolve verifies a selected element on the live page before input.'),
    'fan_page_list': (Search, 'List locally saved Chrome page atlases by title or observed URL.'),
    'fan_page_resolve': (PageElement, 'Resolve a saved page element against the live Chrome page: verify title, observed URL, role/name/link and current accessibility path or a unique OCR/FindText match. Refuses disabled/protected, changed pages, missing or ambiguous targets; never falls back to old coordinates. Returns fresh observed bounds/center for automation.'),
    'fan_page_image': (PageImage, 'Render the persisted full screenshot or a selected element crop from a learned page. element_id omitted selects the whole screenshot. This is historical image evidence, not current click geometry.'),
    'fan_job_config_get': (Empty, 'Read saved job criteria and truthful applicant profile/answers for application planning, only under saved user sharing approval. Export excludes arbitrary settings, credentials and local resume paths.'),
    'fan_job_sharing_get': (Empty, 'Read local sharing permission, approved origins and the fixed api.deepseek.com destination. This setting is not exposed to remote models or MCP.'),
    'fan_job_chrome_pair': (Empty, 'Generate a ten-minute local pairing code for the approved connector in the existing normal Chrome window. Local UI only; never a model/MCP tool.'),
    'fan_job_chrome_status': (Empty, 'Read the selected existing normal Chrome window connection status. Local UI only.'),
    'fan_job_sharing_set': (JobSharing, 'Locally enable/revoke sharing job-site captures, maps and applicant details with api.deepseek.com. Remote models cannot call this tool or change consent.'),
    'fan_job_config_set': (JobConfiguration, 'Locally save selected sites, criteria, resume and truthful answers. browser_execution enables the owned Chrome form adapter; automatic_discovery traverses saved search entry pages. This control is unavailable to remote models.'),
    'fan_job_enqueue': (JobCandidate, 'Add an HTTPS job URL from a configured site to the durable local queue. Already queued URLs return their existing record; nothing is submitted.'),
    'fan_job_status': (Empty, 'Read durable run states, queue counts and job URLs. Submitted requires an observed site receipt. Verification-required and uncertain submissions are never automatically retried.'),
    'fan_job_discover': (JobDiscovery, 'Queue observed job-detail links from a retained page on a configured website, deduplicating tracking URLs. Unknown salaries and locations stay unresolved. Does not navigate, scrape a remote service, fill or submit.'),
    'fan_job_searches': (Empty, 'Build local search entry links for configured roles and locations, plus employer-board discovery links for application platforms without a central search. Nothing is sent until a link is opened.'),
    'fan_job_start': (JobStart, 'Locally start a 0.25..24 hour run (default 8). With saved browser_execution enabled, Chrome discovers jobs, verifies criteria, fills known answers and uploads the selected resume. submit_completed requires verified completeness and a site receipt. Login, verification codes, CAPTCHA and unknown answers require human action.'),
    'fan_job_control': (JobControl, 'Pause, resume or stop an owned local preparation run by run_id. Queue/configuration persist across Fan restarts.'),
    'fan_ocr': (OCR, 'Run the existing Fan OCR library on a window or absolute screen region {x,y,w,h}; return text and observed word/line coordinates.'),
    'fan_pattern_list': (PatternList, 'List FindText patterns already stored in Fan; query filters names/descriptions.'),
    'fan_pattern_search': (PatternSearch, 'Search a stored FindText pattern by name, or omit name and supply explicit FindText text, in current hwnd/region. A supplied name takes priority over text. err1/err0 are foreground/background tolerances from 0 to 0.5; zero means exact with no automatic relaxation. Return observed match bounds/centers; do not guess coordinates.'),
    'fan_pattern_capture': (PatternCapture, "Capture and save a reusable FindText pattern from an explicit current region {x,y,w,h}, each dimension 3..1024 pixels. Existing names require overwrite=true. threshold accepts 0..255, '*128' grayscale or '**50' gray difference (default); descriptions/qualifiers are persisted and indexed. This captures observed pixels, not supplied pattern text."),
    'fan_workflow_list': (WorkflowList, 'List saved native Fan workflow sequences; query filters available names.'),
    'fan_workflow_get': (Named, 'Read a saved Fan workflow with its full structured native steps.'),
    'fan_workflow_save': (WorkflowSave, 'Compose/edit a native Fan workflow from structured step objects using fan_capabilities action schemas. Save into the same sequence library used by the manual editor. Existing names require overwrite=true.'),
    'fan_workflow_preview': (Named, 'Validate and preview a saved native workflow without executing its input actions.'),
    'fan_workflow_run': (WorkflowRun, 'Execute a saved native Fan workflow using the existing sequence engine and input settings. Return actual result; timeout_seconds caps runtime. Stop cancels the native sequence.'),
    'fan_input_settings_get': (Empty, 'Read current native Fan input, timing and automation settings.'),
    'fan_input_settings_set': (InputSettings, 'Configure supported native input/timing settings with a structured object; discover allowed keys through fan_capabilities first.'),
    'fan_library_search': (Search, 'Search the local project AHK library source for functions, signatures and examples. Results contain repo-relative paths/line numbers.'),
    'fan_library_read': (LibraryRead, 'Read bounded lines from a repository-relative .ahk source file. Use real signatures for #Include and script composition; arbitrary file paths are rejected.'),
}

TOOLS.update({
    'fan_window_menu': (MenuProbe, 'Explore observed menu bars: catalog, open an exact observed top label, open a verified submenu, or return with Escape. Each open captures zoned OCR/controls/image and ordered menu items. Leaf commands are never invoked.'),
    'fan_window_probe_item': (ItemProbe, 'Resolve an exact live accessibility path and label. Select a navigation tab only with a known return tab, or expand a collapsed tree branch. Never invokes generic buttons/leaf file items. Returns live evidence and a return target.'),
    'fan_desktop_preview': (Empty, 'Capture a local scaled mini desktop with virtual-screen origin and cursor metadata. No image is sent to a provider by this tool; it is for the native validation viewer.'),
    'daa_explore': (Explore, 'Bounded branching interface exploration: open each observed menu and safe submenu, record ordered zoned evidence, then return; probe navigation tabs/collapsed branches and return. Stops on uncertainty or a chain budget. Never clicks arbitrary command buttons.'),
    'daa_chain_status': (ChainStatus, 'Read numbered interactions, parent/caller origin, branch, results and remaining chain budget for this task.'),
    'daa_unit_save': (UnitSave, 'Save a local Python-orchestrated sequence of typed tools and explicit expected result fields. AHK script revisions are pinned; inputs use {$input:"field"}, prior results {$result:"step.field"}. No shell/eval or model is used in replay.'),
    'daa_unit_run': (UnitRun, 'Execute an existing local automation unit with typed inputs, exact pinned AHK revisions and fail-fast explicit postconditions. No model or source rewriting. Every tool/branch is traced.'),
    'daa_unit_list': (Search, 'Find saved local automation units for reuse; inspect their catalog content before composing new steps.'),
    'daa_explorer_usage': (Search, 'Read task-relevant Explorer path rankings by non-idle foreground time and visits. A relevant query is required for agent tasks; full path history remains local.'),
    'daa_trace': (TraceStep, 'Instrument an AHK/Python action before/after input: label, current HWND, optional observed physical x/y and evidence. Produces a numbered chain entry and mini-desktop hotspot. Logging alone is not proof the input occurred.'),
    'daa_cue': (TourCue, 'Show a narration cue in the native workbench; pause briefly or wait for the operator Continue tour button. Cancels/timeouts stop the workflow. Does not start OBS, record audio, or speak on the user\'s behalf.'),
})

FAN_TOOLS = {name for name in TOOLS if name.startswith('fan_')}
LOCAL_PAGE_TOOLS = {'fan_page_learn', 'fan_page_probe', 'fan_page_list', 'fan_page_get', 'fan_page_resolve', 'fan_page_image'}
LOCAL_JOB_TOOLS = {name for name in TOOLS if name.startswith('fan_job_')}
APPROVED_JOB_TOOLS = LOCAL_PAGE_TOOLS | {'fan_job_config_get', 'fan_job_status', 'fan_job_searches', 'fan_job_discover'}
JOB_READ_ONLY_TOOLS = LOCAL_PAGE_TOOLS | {'fan_job_config_get', 'fan_job_status', 'fan_job_searches', 'window_list', 'window_active'}
SCRIPT_TOOLS = {name for name in TOOLS if name.startswith('ahk_script_')}
CATALOG_TOOLS = {name for name in TOOLS if name.startswith('tool_catalog_') or name.startswith('knowledge_')}


def functions() -> list[dict]:
    result = []
    from .job_sharing import enabled
    share_jobs = enabled()
    for name, (model, description) in TOOLS.items():
        if name in LOCAL_PAGE_TOOLS | LOCAL_JOB_TOOLS and not (share_jobs and name in APPROVED_JOB_TOOLS):
            continue
        schema = model.model_json_schema()
        schema.pop('title', None)
        result.append({'type': 'function', 'function': {
            'name': name, 'description': description, 'parameters': schema}})
    return result


def validate(name: str, arguments: dict) -> dict:
    return TOOLS[name][0].model_validate(arguments).model_dump(exclude_none=True, exclude_unset=True)


def signature_guide() -> str:
    """Short human-readable inventory supplements the exact function schemas."""
    lines = []
    from .job_sharing import enabled
    share_jobs = enabled()
    for name, (model, _) in TOOLS.items():
        if name in LOCAL_PAGE_TOOLS | LOCAL_JOB_TOOLS and not (share_jobs and name in APPROVED_JOB_TOOLS):
            continue
        fields = []
        for key, field in model.model_fields.items():
            fields.append(key if field.is_required() else key + '=?')
        lines.append(name + '(' + ', '.join(fields) + ')')
    return '\n'.join(lines)
