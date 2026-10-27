from __future__ import annotations

import collections
import json
import math
import re
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Iterable


COMMON_SKILLS = {
    "python", "c#", "c++", "c", "javascript", "typescript", "html", "css",
    "sql", "t-sql", "sqlite", "mongodb", "azure", "aws", "cloud",
    "asp.net", ".net", "blazor", "mvc", "mvvm", "rest", "api", "git",
    "github", "ci/cd", "docker", "linux", "ubuntu", "windows", "powershell",
    "autohotkey", "rpa", "ocr", "opencv", "cuda", "yolo", "computer vision",
    "machine learning", "ai", "embedded systems", "embedded software", "arduino",
    "esp32", "esp8266", "microcontroller", "iot", "can bus", "can", "modbus",
    "uart", "serial", "electronics", "avionics", "multimeter", "schematics",
    "troubleshooting", "cnc", "scrum", "tdd", "unit testing", "integration testing",
    "repository pattern", "clean architecture", "design patterns", "big o",
    "leadership", "communication", "teaching", "video production", "broadcasting",
}

ACTION_VERBS = {
    "achieved", "analyzed", "architected", "automated", "built", "created",
    "decreased", "delivered", "designed", "developed", "diagnosed", "directed",
    "engineered", "executed", "implemented", "improved", "increased", "integrated",
    "led", "maintained", "managed", "mentored", "optimized", "produced", "reduced",
    "resolved", "shipped", "streamlined", "supported", "taught", "tested",
    "trained", "troubleshot", "validated", "wrote",
}

SECTION_ALIASES = {
    "summary": ("professional summary", "summary", "profile", "objective"),
    "skills": ("skills", "technical skills", "skills & experience", "competencies"),
    "experience": ("professional experience", "work experience", "employment", "experience"),
    "education": ("education", "training", "certifications", "certification"),
    "projects": ("projects", "personal projects", "portfolio"),
}

STOP_WORDS = {
    "a", "an", "and", "are", "as", "at", "be", "been", "being", "by", "can",
    "for", "from", "has", "have", "in", "into", "is", "it", "its", "of", "on",
    "or", "our", "that", "the", "their", "this", "to", "using", "we", "will",
    "with", "you", "your", "job", "role", "work", "team", "candidate", "required",
    "preferred", "experience", "years", "skills", "ability", "including", "such",
}


@dataclass
class ATSMetric:
    name: str
    score: float
    maximum: float
    status: str
    explanation: str

    @property
    def percent(self) -> float:
        return 0.0 if self.maximum <= 0 else self.score / self.maximum * 100.0


@dataclass
class ATSReport:
    overall_score: float
    pages: int
    words: int
    characters: int
    metrics: list[ATSMetric]
    matched_keywords: list[str]
    missing_keywords: list[str]
    detected_skills: list[str]
    sections_found: list[str]
    quantified_statements: int
    action_verb_hits: int
    warnings: list[str]
    tips: list[str]
    resume_text: str
    job_description: str

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["metrics"] = [asdict(metric) | {"percent": metric.percent} for metric in self.metrics]
        return data


def normalize_text(text: str) -> str:
    text = text.replace("\u00a0", " ").replace("\u200b", "")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n[ \t]+", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def extract_pdf_text(path: str | Path) -> tuple[str, int, list[str]]:
    try:
        from pypdf import PdfReader
    except ImportError as exc:
        raise RuntimeError(
            "PDF scanning requires pypdf. Use Setup & Models > Install Python dependencies."
        ) from exc

    pdf_path = Path(path).expanduser().resolve()
    if not pdf_path.exists():
        raise FileNotFoundError(pdf_path)
    reader = PdfReader(str(pdf_path))
    page_texts = [normalize_text(page.extract_text() or "") for page in reader.pages]
    return normalize_text("\n\n".join(page_texts)), len(reader.pages), page_texts


def _contains_any(text_lower: str, variants: Iterable[str]) -> bool:
    return any(variant.lower() in text_lower for variant in variants)


def _skill_present(text_lower: str, skill: str) -> bool:
    raw_skill = skill.lower().strip().strip(".,;:()[]{}")
    if raw_skill in {"c++", "c#", ".net", "ci/cd", "t-sql"}:
        return raw_skill in text_lower
    normalized_text = re.sub(r"[-_/]+", " ", text_lower)
    normalized_text = re.sub(r"\s+", " ", normalized_text)
    normalized_skill = re.sub(r"[-_/]+", " ", raw_skill)
    normalized_skill = re.sub(r"\s+", " ", normalized_skill).strip()
    escaped = re.escape(normalized_skill)
    return re.search(rf"\b{escaped}\b", normalized_text) is not None


def detected_skills(text: str) -> list[str]:
    lower = text.lower()
    return sorted(skill for skill in COMMON_SKILLS if _skill_present(lower, skill))


def extract_job_keywords(job_description: str, limit: int = 35) -> list[str]:
    if not job_description.strip():
        return []
    lower = job_description.lower()
    skill_matches = [skill for skill in COMMON_SKILLS if _skill_present(lower, skill)]

    tokens = [
        token.strip(".,;:()[]{}-/")
        for token in re.findall(r"[a-z][a-z0-9+#.\-/]{2,}", lower)
    ]
    counts = collections.Counter(
        token for token in tokens if token and token not in STOP_WORDS
    )
    generic = [word for word, _count in counts.most_common(limit * 2)]

    phrases = []
    phrase_candidates = re.findall(
        r"\b(?:embedded software|computer vision|machine learning|object oriented|"
        r"unit testing|integration testing|clean architecture|design patterns|"
        r"can bus|cloud development|fleet management|technical support|"
        r"project management|problem solving|root cause|continuous integration)\b",
        lower,
    )
    phrases.extend(phrase_candidates)

    ordered: list[str] = []
    for item in skill_matches + phrases + generic:
        item = item.strip()
        if item and item not in ordered:
            ordered.append(item)
        if len(ordered) >= limit:
            break
    return ordered


def _readability_score(text: str) -> float:
    words = re.findall(r"\b\w+\b", text)
    sentences = [segment for segment in re.split(r"[.!?]+", text) if segment.strip()]
    if not words or not sentences:
        return 0.0
    average_sentence = len(words) / len(sentences)
    if 10 <= average_sentence <= 24:
        return 1.0
    if 7 <= average_sentence <= 32:
        return 0.75
    if 5 <= average_sentence <= 40:
        return 0.5
    return 0.25


def analyze_resume(
    resume_text: str,
    *,
    pages: int = 0,
    job_description: str = "",
) -> ATSReport:
    text = normalize_text(resume_text)
    lower = text.lower()
    words = re.findall(r"\b[\w+#./-]+\b", text)
    word_count = len(words)

    email_found = bool(re.search(r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}", text))
    phone_found = bool(re.search(r"(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]\d{3}[-.\s]\d{4}", text))
    linkedin_found = "linkedin" in lower
    github_found = "github" in lower
    contact_points = sum((email_found, phone_found, linkedin_found, github_found))
    contact_score = min(10.0, contact_points * 2.5)

    sections_found = [
        key for key, aliases in SECTION_ALIASES.items() if _contains_any(lower, aliases)
    ]
    section_score = min(15.0, len(sections_found) / len(SECTION_ALIASES) * 15.0)

    skills = detected_skills(text)
    skill_score = min(15.0, len(skills) / 18.0 * 15.0)

    job_keywords = extract_job_keywords(job_description)
    matched: list[str] = []
    missing: list[str] = []
    for keyword in job_keywords:
        if _skill_present(lower, keyword):
            matched.append(keyword)
        else:
            missing.append(keyword)
    if job_keywords:
        keyword_score = len(matched) / len(job_keywords) * 25.0
        keyword_explanation = (
            f"Matched {len(matched)} of {len(job_keywords)} high-signal job-description terms."
        )
    else:
        keyword_score = min(25.0, len(skills) / 22.0 * 25.0)
        keyword_explanation = (
            "No job description was supplied; this score measures general technical keyword coverage."
        )

    quantified_patterns = re.findall(
        r"(?:\$\s?\d[\d,]*(?:\.\d+)?|\b\d+(?:\.\d+)?\s?%|\b\d+\+?\s+(?:years?|projects?|users?|queries?|vehicles?|applications?|students?|systems?|months?))",
        lower,
    )
    quantified_count = len(quantified_patterns)
    quantified_score = min(10.0, quantified_count / 6.0 * 10.0)

    action_hits = sum(
        len(re.findall(rf"\b{re.escape(verb)}\b", lower)) for verb in ACTION_VERBS
    )
    action_score = min(10.0, action_hits / 12.0 * 10.0)

    extraction_ratio = len(text.strip()) / max(1, pages)
    extraction_score = 5.0 if extraction_ratio >= 700 else max(0.0, extraction_ratio / 700 * 5.0)
    readable = _readability_score(text)
    formatting_score = extraction_score + readable * 5.0

    if 450 <= word_count <= 1100:
        length_score = 5.0
        length_status = "Good"
    elif 300 <= word_count <= 1400:
        length_score = 3.5
        length_status = "Review"
    else:
        length_score = 2.0
        length_status = "Weak"

    metrics = [
        ATSMetric(
            "Contact and links",
            contact_score,
            10.0,
            "Good" if contact_score >= 7.5 else "Review",
            f"Detected email={email_found}, phone={phone_found}, LinkedIn={linkedin_found}, GitHub={github_found}.",
        ),
        ATSMetric(
            "Recognizable sections",
            section_score,
            15.0,
            "Good" if section_score >= 12 else "Review",
            "Detected: " + (", ".join(sections_found) if sections_found else "none"),
        ),
        ATSMetric(
            "Technical skill coverage",
            skill_score,
            15.0,
            "Good" if skill_score >= 11 else "Review",
            f"Detected {len(skills)} known skills or technical concepts.",
        ),
        ATSMetric(
            "Job-description alignment",
            keyword_score,
            25.0,
            "Good" if keyword_score >= 17 else ("Review" if keyword_score >= 10 else "Weak"),
            keyword_explanation,
        ),
        ATSMetric(
            "Quantified impact",
            quantified_score,
            10.0,
            "Good" if quantified_score >= 6.5 else "Weak",
            f"Detected {quantified_count} quantified result or scale statements.",
        ),
        ATSMetric(
            "Action-oriented language",
            action_score,
            10.0,
            "Good" if action_score >= 6.5 else "Review",
            f"Detected {action_hits} action-verb occurrences.",
        ),
        ATSMetric(
            "PDF extraction and readability",
            formatting_score,
            10.0,
            "Good" if formatting_score >= 7.5 else "Review",
            "Measures whether text extracts cleanly and whether sentence length is reasonably readable.",
        ),
        ATSMetric(
            "Resume length",
            length_score,
            5.0,
            length_status,
            f"Detected {word_count} words across {pages or '?'} page(s).",
        ),
    ]

    overall = round(sum(metric.score for metric in metrics), 1)
    warnings: list[str] = []
    tips: list[str] = []

    if pages > 2:
        warnings.append(
            f"The resume is {pages} pages. Many targeted applications benefit from a tighter 1-2 page version."
        )
        tips.append(
            "Create a role-specific 1-2 page resume and keep the full multi-page document as a master resume."
        )
    if quantified_count < 4:
        warnings.append("Few bullets show measurable scope, speed, quality, cost, or outcome.")
        tips.append(
            "Add truthful numbers: users supported, vehicles tracked, queries written, projects completed, students taught, time saved, defect reduction, or equipment repaired."
        )
    if job_keywords and missing:
        tips.append(
            "Use exact job-description terms only when they truthfully describe your work. Highest-priority missing terms: "
            + ", ".join(missing[:12])
            + "."
        )
    if "embedded software" in lower or "embedded-software" in lower:
        tips.append(
            "For embedded roles, move embedded systems, C/C++, CAN, UART, ESP32/Arduino, electronics troubleshooting, and avionics nearer the top."
        )
    if "computer vision" in lower or "opencv" in lower:
        tips.append(
            "For computer-vision roles, add a compact projects section with repository links, datasets/cameras used, latency or accuracy measurements, and deployment hardware."
        )
    if "built" in lower and quantified_count < 6:
        tips.append(
            "Convert project descriptions from feature lists into accomplishment bullets: action + system + scale + result."
        )
    if not job_description.strip():
        tips.append(
            "Paste the exact job description before scoring. ATS-style matching is most useful when measured against one specific role."
        )
    tips.extend(
        [
            "Keep standard headings such as Summary, Skills, Experience, Education, Certifications, and Projects.",
            "Use simple single-column text, ordinary fonts, and real text rather than text embedded in images.",
            "Put the strongest matching skills and evidence in the top third of the first page.",
            "Do not keyword-stuff. Every keyword should be supported by a project, job, certification, or education entry.",
            "Keep dates, employer names, titles, and certification names consistent across the resume, LinkedIn, and application form.",
        ]
    )

    return ATSReport(
        overall_score=overall,
        pages=pages,
        words=word_count,
        characters=len(text),
        metrics=metrics,
        matched_keywords=matched,
        missing_keywords=missing,
        detected_skills=skills,
        sections_found=sections_found,
        quantified_statements=quantified_count,
        action_verb_hits=action_hits,
        warnings=warnings,
        tips=list(dict.fromkeys(tips)),
        resume_text=text,
        job_description=job_description,
    )


def donovan_seed_profile(resume_path: str | Path) -> dict[str, Any]:
    """Create a reviewable profile using only facts explicitly present in the supplied resume."""
    path = str(Path(resume_path).expanduser().resolve())
    return {
        "schema_version": 2,
        "identity": {
            "first_name": "Donovan",
            "middle_name": "",
            "last_name": "Zeanah",
            "preferred_name": "",
            "email": "DKZeanah@gmail.com",
            "phone": "(205) 799-1734",
            "address_line_1": "",
            "address_line_2": "",
            "city": "",
            "state": "",
            "postal_code": "",
            "country": "United States",
        },
        "links": {
            "linkedin": "",
            "github": "",
            "portfolio": "",
            "website": "",
        },
        "current_work": {
            "employer": "Atlanta Technical College",
            "title": "Avionics bench technician program",
            "start_date": "2025",
        },
        "education": {
            "school": "Atlanta Technical College",
            "degree": "Year-long avionics bench technician program",
            "field_of_study": "Avionics / aircraft electronics",
            "graduation_date": "2026",
        },
        "documents": {
            "resume_path": path,
            "cover_letter_path": "",
        },
        "skills": [
            "Python", "C#", "C", "C++", "HTML", "CSS", "JavaScript",
            "Azure", "ASP.NET", "MVC", "MVVM", "Blazor", "T-SQL", "SQLite",
            "MongoDB", "Object-oriented programming", "Design patterns",
            "Repository pattern", "Vertical Slice architecture", "Big O notation",
            "Arduino", "ESP8266", "ESP32", "IoT", "CAN bus", "Modbus", "UART",
            "Serial communication", "Windows API automation", "RPA", "OCR",
            "AutoHotkey", "YOLO", "OpenCV", "CUDA", "Ubuntu", "IP cameras",
            "Live streaming", "Digital media production", "Electronics troubleshooting",
            "Electrical schematics", "Multimeter use", "CNC operation",
            "Unit testing", "Integration testing", "Git", "GitHub", "CI/CD",
        ],
        "work_history": [
            {
                "employer": "TheCoderSchool",
                "title": "Programming instructor",
                "dates": "2025-2026",
                "highlights": [
                    "Taught children and young adults programming fundamentals in one-on-one and group settings."
                ],
            },
            {
                "employer": "Machine Metal Components",
                "title": "CNC operation and maintenance",
                "dates": "2024-2025",
                "highlights": [
                    "Operated and maintained mills and laser equipment.",
                    "Performed manual machine operations using drills and mills.",
                ],
            },
            {
                "employer": "Mercedes-Benz via Actalent",
                "title": "Software development / vehicle integration testing",
                "dates": "2023-2024",
                "highlights": [
                    "Built an in-house fleet management application with Blazor, .NET 8, SQLite, and T-SQL.",
                    "Performed vehicle integration testing focused on main-display and UI functions.",
                    "Performed CAN-based diagnostics and troubleshooting.",
                ],
            },
            {
                "employer": "Department of the Navy",
                "title": "Mass Communication Specialist",
                "dates": "2016-2022",
                "highlights": [
                    "Video broadcaster and media producer at Defense Media Activity / Armed Forces Network, Yokota Air Base, Tokyo.",
                    "Produced live broadcasts, scripts, graphics, animations, storyboards, print media, and video productions.",
                ],
            },
        ],
        "education_history": [
            {
                "institution": "Atlanta Technical College",
                "program": "Avionics bench technician",
                "dates": "2025-2026",
            },
            {
                "institution": "Microsoft Software and Systems Academy",
                "program": "Cloud Application Developer track",
                "dates": "2022-2023",
            },
        ],
        "certifications": [
            {
                "name": "ASTM NCATT Aircraft Electronics Technician (AET) exam",
                "year": "2026",
                "status": "Resume states exam passed",
            }
        ],
        "verified_facts": [
            "Navy veteran with six years of honorable service.",
            "Interested in embedded software development, computer vision, AI, electronics, and smart workshops.",
            "Built an in-house fleet-management application using Blazor, .NET 8, SQLite, and T-SQL.",
            "Has personal projects in OS automation, C#, Python, geodesic-dome rendering, PTZ camera control, media analysis, and Arduino systems.",
            "Resume references a LinkedIn profile and GitHub projects but does not expose exact URLs in extracted text; verify URLs before adding them.",
        ],
        "preferences": {
            "remote": "",
            "locations": [],
            "minimum_salary": "",
            "target_roles": [
                "Embedded Software Developer",
                "Computer Vision Developer",
                "Automation Developer",
                "Avionics / Electronics Technician",
            ],
        },
        "notes": (
            "Seeded from DonovanZeanahResume-2026.pdf. Review every field before using it. "
            "Address, exact LinkedIn URL, exact GitHub URL, work authorization, compensation, "
            "and other sensitive or missing facts were intentionally not inferred."
        ),
    }


def profile_metrics(profile: dict[str, Any], report: ATSReport | None = None) -> dict[str, Any]:
    work_history = profile.get("work_history", [])
    education_history = profile.get("education_history", [])
    skills = profile.get("skills", [])
    facts = profile.get("verified_facts", [])
    data = {
        "verified_identity_fields": sum(
            bool(value) for value in profile.get("identity", {}).values()
        ),
        "skills": len(skills),
        "work_history_entries": len(work_history),
        "education_entries": len(education_history),
        "verified_facts": len(facts),
        "certifications": len(profile.get("certifications", [])),
        "target_roles": len(profile.get("preferences", {}).get("target_roles", [])),
    }
    if report:
        data.update(
            {
                "resume_pages": report.pages,
                "resume_words": report.words,
                "ats_baseline_score": report.overall_score,
                "detected_resume_skills": len(report.detected_skills),
                "quantified_statements": report.quantified_statements,
            }
        )
    return data


def build_ai_resume_prompt(report: ATSReport, target_role: str = "") -> str:
    compact = {
        "overall_score": report.overall_score,
        "metrics": [
            {
                "name": metric.name,
                "score": metric.score,
                "maximum": metric.maximum,
                "explanation": metric.explanation,
            }
            for metric in report.metrics
        ],
        "matched_keywords": report.matched_keywords,
        "missing_keywords": report.missing_keywords,
        "warnings": report.warnings,
        "tips": report.tips,
    }
    return (
        "Act as a careful resume reviewer, not a hiring decision-maker. Analyze the resume "
        "against the supplied job description and deterministic ATS-style measurements. "
        "Do not invent experience, credentials, dates, metrics, URLs, or qualifications.\n\n"
        f"TARGET ROLE:\n{target_role or 'Not specified'}\n\n"
        f"DETERMINISTIC REPORT:\n{json.dumps(compact, indent=2)}\n\n"
        f"JOB DESCRIPTION:\n{report.job_description or 'Not supplied'}\n\n"
        f"RESUME TEXT:\n{report.resume_text}\n\n"
        "Return these sections: 1) strongest evidence, 2) likely ATS weaknesses, "
        "3) missing or weakly supported keywords, 4) bullet rewrites that preserve truth, "
        "5) top-third-of-page recommendation, 6) questions the applicant must answer before editing."
    )


def profile_is_effectively_blank(profile: dict[str, Any]) -> bool:
    identity = profile.get("identity", {})
    meaningful_identity = any(
        str(identity.get(key, "")).strip()
        for key in ("first_name", "last_name", "email", "phone", "address_line_1", "city", "state")
    )
    return not (
        meaningful_identity
        or profile.get("skills")
        or profile.get("work_history")
        or profile.get("education_history")
        or profile.get("verified_facts")
    )
