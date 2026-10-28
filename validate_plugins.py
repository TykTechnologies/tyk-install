#!/usr/bin/env python3
"""
Validate this repository against Agent Plugins 1.0.0, and against itself.

Two kinds of check:

  * the portable contract - what a conformant client will reject or skip a plugin
    for (manifest schema, skill frontmatter, path containment);
  * the anti-drift check - every repository path named in the topology matrix must
    exist, and every `guidance-only` row must NOT have one. A renamed or deleted
    deployment directory then fails here instead of silently breaking a skill at
    the moment a customer relies on it.

    python3 validate_plugins.py

Spec: https://agent-plugins.org  |  Skills: https://agentskills.io/specification
Deliberately dependency-free so it runs anywhere, including CI.
"""
import json
import os
import re
import sys

SCHEMA_ID = "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
MANIFEST_FIELDS = {"$schema", "name", "version", "description", "author",
                   "homepage", "repository", "license", "keywords", "extensions"}
AUTHOR_FIELDS = {"name", "email", "url"}
PLUGIN_NAME = re.compile(r"(?!.*(?:--|\.\.))[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?")
SKILL_NAME = re.compile(r"[a-z0-9]+(-[a-z0-9]+)*")
SKILL_DIRS = {"SKILL.md", "scripts", "references", "assets"}

REPO = os.path.dirname(os.path.abspath(__file__))
MATRIX = os.path.join(REPO, "skills", "tyk-deployment-planner",
                      "references", "topology-matrix.md")


class Report:
    def __init__(self, label):
        self.label = label
        self.rows = []

    def check(self, ok, rule, detail=""):
        self.rows.append(("ok" if ok else "FAIL", rule, detail))
        return bool(ok)

    def note(self, rule):
        self.rows.append(("note", rule, ""))

    @property
    def failed(self):
        return [r for r in self.rows if r[0] == "FAIL"]

    @property
    def checks(self):
        return [r for r in self.rows if r[0] != "note"]

    def print(self):
        print(f"\n{self.label}")
        for status, rule, detail in self.rows:
            mark = {"ok": "  ok  ", "FAIL": "  FAIL", "note": "  --  "}[status]
            print(f"{mark} {rule}" + (f"   [{detail}]" if detail and status == "FAIL" else ""))


def frontmatter(path):
    m = re.match(r"^---\n(.*?)\n---\n", open(path, encoding="utf-8").read(), re.S)
    if not m:
        return None
    body, out = m.group(1), {}
    for key in ("name", "description", "license", "compatibility", "allowed-tools"):
        f = re.search(rf"^{key}:\s*(.+?)(?=\n[a-z-]+:|\Z)", body, re.M | re.S)
        if f:
            out[key] = f.group(1).strip()
    return out


def validate_manifest(r, path):
    manifest = os.path.join(path, "plugin.json")
    if not r.check(os.path.isfile(manifest), "§4.1 manifest exists at plugin.json"):
        return None
    try:
        m = json.load(open(manifest, encoding="utf-8"))
    except json.JSONDecodeError as e:
        r.check(False, "§5.2 manifest is valid JSON", str(e))
        return None

    r.check(isinstance(m, dict), "§5.2 manifest is a top-level object")
    unknown = set(m) - MANIFEST_FIELDS
    r.check(not unknown, "§5.2 manifest schema is closed", f"unknown: {sorted(unknown)}")
    r.check(m.get("$schema") == SCHEMA_ID, "§5.2 $schema is the canonical 1.0.0 id",
            repr(m.get("$schema")))
    name = m.get("name")
    r.check(isinstance(name, str) and 1 <= len(name) <= 64,
            "§5.3 name present and 1-64 chars", repr(name))
    r.check(isinstance(name, str) and bool(PLUGIN_NAME.fullmatch(name)),
            "§5.5 name matches the required pattern", repr(name))
    if "author" in m:
        r.check(isinstance(m["author"], dict) and set(m["author"]) <= AUTHOR_FIELDS,
                "§5.4 author has only name/email/url")
    if "keywords" in m:
        r.check(isinstance(m["keywords"], list)
                and all(isinstance(k, str) for k in m["keywords"]),
                "§5.4 keywords is an array of strings")
    return m


def validate_skills(r, path):
    skills_dir = os.path.join(path, "skills")
    if not r.check(os.path.isdir(skills_dir), "§6.2 skills/ is a directory"):
        return
    # §7.1 - immediate children only, no recursive search
    skills = sorted(d for d in os.listdir(skills_dir)
                    if os.path.isfile(os.path.join(skills_dir, d, "SKILL.md")))
    r.check(skills, "§7.1 skills/ has at least one skill with SKILL.md")
    for s in skills:
        sp = os.path.join(skills_dir, s)
        fm = frontmatter(os.path.join(sp, "SKILL.md"))
        r.check(fm is not None, f"[{s}] SKILL.md has YAML frontmatter")
        if fm is None:
            continue
        r.check(fm.get("name") == s, f"[{s}] name matches its directory",
                f"{fm.get('name')!r} vs {s!r}")
        r.check(bool(SKILL_NAME.fullmatch(fm.get("name", ""))) and len(fm["name"]) <= 64,
                f"[{s}] name is lowercase/hyphenated, <=64 chars")
        desc = fm.get("description", "")
        r.check(0 < len(desc) <= 1024, f"[{s}] description is 1-1024 chars",
                f"{len(desc)} chars")
        # Referenced reference files must exist, or progressive disclosure dead-ends.
        body = open(os.path.join(sp, "SKILL.md"), encoding="utf-8").read()
        for ref in sorted(set(re.findall(r"`(references/[\w./-]+\.md)`", body))):
            r.check(os.path.isfile(os.path.join(sp, ref)),
                    f"[{s}] {ref} exists")
        extra = sorted(set(os.listdir(sp)) - SKILL_DIRS)
        if extra:
            r.note(f"[{s}] extra entries (allowed, not auto-loaded): {', '.join(extra)}")


def validate_containment(r, path):
    root = os.path.realpath(path)
    escaped = []
    for dp, dirnames, filenames in os.walk(path):
        if ".git" in dirnames:
            dirnames.remove(".git")
        for f in filenames:
            p = os.path.join(dp, f)
            if not os.path.realpath(p).startswith(root + os.sep):
                escaped.append(os.path.relpath(p, path))
    r.check(not escaped, "§4.1 all package paths stay within the plugin root",
            str(escaped[:3]))


def validate_matrix(r, path):
    """Anti-drift: paths the matrix promises must match what the repo actually has."""
    if not r.check(os.path.isfile(MATRIX), "topology matrix exists"):
        return
    text = open(MATRIX, encoding="utf-8").read()
    # The status cell may carry qualifying prose after the backticked status, e.g.
    # "`bundled-tested` (gateway; dashboard and pump `bundled`)". Anchoring on a
    # closing pipe silently dropped those rows -- and the row with the most
    # nuanced status was the one row losing its anti-drift check.
    rows = re.findall(
        r"^\|\s*[^|]+\|\s*`([^`]+)`\s*\|[^\n]*?`(bundled-tested|bundled|guidance-only)`",
        text, re.M)
    r.check(rows, "topology matrix has parseable rows", f"found {len(rows)}")
    # Every table row naming a directory must be one of them, or a row is being
    # skipped without anyone noticing. Only deployment rows count: the status
    # legend at the top of the file also carries backticked statuses, but has no
    # path cell.
    present = len([l for l in text.splitlines()
                   if l.startswith("|")
                   and re.search(r"`(bundled-tested|bundled|guidance-only)`", l)
                   and re.search(r"`[^`]*/[^`]*`", l)])
    r.check(len(rows) == present,
            "every status-bearing matrix row was parsed",
            f"parsed {len(rows)} of {present} rows")
    seen = set()
    for target, status in rows:
        target = target.strip()
        if target in seen:
            continue
        seen.add(target)
        full = os.path.join(path, target)
        exists = os.path.exists(full)
        if status == "guidance-only":
            r.check(not exists, f"guidance-only row has no artifact: {target}",
                    "a directory exists, so this row understates what is available")
        else:
            r.check(exists, f"{status} row resolves to a real path: {target}",
                    "path named in the matrix does not exist")
    print(f"       ({len(seen)} distinct paths checked against the matrix)")


NATIVE = {
    "Claude Code plugin": ".claude-plugin/plugin.json",
    "Claude Code marketplace": ".claude-plugin/marketplace.json",
    "Codex plugin": ".codex-plugin/plugin.json",
    "Codex marketplace": ".agents/plugins/marketplace.json",
}


def validate_native_packaging(r, path):
    """The neutral manifest is the contract; these are what `claude plugin install`
    and `codex plugin add` actually read. They must describe the same plugin."""
    with open(os.path.join(path, "plugin.json"), encoding="utf-8") as f:
        portable = json.load(f)
    name, version = portable.get("name"), portable.get("version")
    loaded = {}
    for label, rel in NATIVE.items():
        full = os.path.join(path, rel)
        if not r.check(os.path.isfile(full), f"{label} manifest exists at {rel}"):
            continue
        try:
            with open(full, encoding="utf-8") as f:
                loaded[label] = json.load(f)
        except ValueError as e:
            r.check(False, f"{label} manifest is valid JSON", str(e))
    for label in ("Claude Code plugin", "Codex plugin"):
        m = loaded.get(label)
        if m is None:
            continue
        r.check(m.get("name") == name, f"{label} name matches plugin.json",
                f"{m.get('name')!r} != {name!r}")
        r.check(m.get("version") == version, f"{label} version matches plugin.json",
                f"{m.get('version')!r} != {version!r}")
        r.check(m.get("skills") == "./skills/", f"{label} loads skills from ./skills/",
                repr(m.get("skills")))
    for label in ("Claude Code marketplace", "Codex marketplace"):
        m = loaded.get(label)
        if m is None:
            continue
        entries = m.get("plugins") or []
        r.check(len(entries) == 1 and entries[0].get("name") == name,
                f"{label} lists exactly this plugin", repr([e.get("name") for e in entries]))
        src = entries[0].get("source") if entries else None
        root = src == "./" or (isinstance(src, dict) and src.get("path") == "./")
        r.check(root, f"{label} entry points at the repository root", repr(src))
    claude_mp = loaded.get("Claude Code marketplace")
    if claude_mp and claude_mp.get("plugins"):
        r.check(claude_mp["plugins"][0].get("version") == version,
                "Claude Code marketplace version matches plugin.json")


def main():
    if not os.path.isfile(os.path.join(REPO, "plugin.json")):
        print("no plugin.json at the repository root")
        return 1

    r = Report(f"plugin: {os.path.basename(REPO)}")
    if validate_manifest(r, REPO) is not None:
        validate_containment(r, REPO)
        validate_skills(r, REPO)
        validate_matrix(r, REPO)
        validate_native_packaging(r, REPO)
    r.print()

    bad, total = len(r.failed), len(r.checks)
    print(f"\n{total - bad}/{total} checks passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
