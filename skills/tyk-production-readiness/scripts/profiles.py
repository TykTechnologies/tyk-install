#!/usr/bin/env python3
"""
Read Tyk deployment guidance out of this repository's own config files.

Every tuning decision in tyk-install is already written down, as a marker comment
next to the setting it applies to:

    TYK_GW_LOGLEVEL=info # PROD: Set to "error" to reduce log volume
    # TYK_GW_MAXIDLECONNSPERHOST=10000 # PROD/PERFORMANCE: Set high value (>=10000)
    TYK_GW_SECRET=352d... # SECURITY: Change to a strong 32+ character string

    # -------------------------------------------------------------------------
    # Required for deploying on RedHat OpenShift
    # -------------------------------------------------------------------------
    # securityContext:
    #   runAsUser: null

This script is the only place that knows how to read those markers, so the
guidance stays in the config files where engineers already maintain it instead of
being duplicated into documentation that drifts.

    profiles.py list   <file>...                       what markers a file carries
    profiles.py audit  <file>... [--profile P]...       settings vs recommendations
    profiles.py apply  <file> --profile P... [-o OUT]   emit an overlay

`audit` reports, and is the mode to use. `apply` generates an overlay only for
`--profile openshift`, whose blocks are genuine "uncomment to use" recommendations
that graft as new mappings. It refuses prod/performance/security: their commented
values are often illustrative defaults rather than recommendations, and on Helm an
emitted list replaces the base list instead of merging with it. Run `apply` with
one of those to see the full explanation.

Deliberately dependency-free (no PyYAML) so it runs in whatever environment the
agent is given. `apply` therefore emits text rather than round-tripping a parsed
document, and the real guard on its output is `helm template` for Helm values and
`docker compose config` for env files.

Spec: https://tyk.io/docs/planning-for-production
"""
import argparse
import os
import re
import sys

# A marker may serve more than one profile: PROD/PERFORMANCE settings are
# relevant both to someone hardening for production and to someone chasing
# throughput, so it resolves to both.
#
# Two accepted forms, and the distinction matters:
#
#   "PROD: set to error"          -> marker plus colon. Any case.
#   "in PROD set to false"        -> no colon, so the word must be UPPERCASE.
#
# Requiring only a word boundary and an optional colon (as an earlier version did)
# made ordinary section headers register as guidance: "# Security settings" and
# "# Security & configuration" both became security findings, so a file with zero
# `# SECURITY:` annotations reported three. Real colon-less usage is always caps,
# and headers are Title Case, so case is the discriminator.
_FAMILIES = [
    (r"P?PROD\s*/\s*PERFORMANCE", ("prod", "performance")),
    (r"PROD", ("prod",)),
    (r"SECURITY", ("security",)),
]
MARKERS = [
    # (with-colon pattern, caps-only pattern, profiles)
    (re.compile(rf"\b{word}\b\s*:", re.I), re.compile(rf"\b{word}\b"), profiles)
    for word, profiles in _FAMILIES
]
OPENSHIFT_BANNER = re.compile(r"Required for (?:deploying|installing) on RedHat OpenShift", re.I)

ALL_PROFILES = ("prod", "performance", "security", "openshift")

# KEY=value with a trailing marker comment, optionally commented out itself.
ENV_LINE = re.compile(
    r"""^(?P<off>\#\s*)?                    # leading '#' when only suggested
         (?P<key>[A-Za-z][A-Za-z0-9_]*)     # TYK_GW_..., and mixed case:
                                            # DashDatabaseConnectionString is real
         =(?P<val>[^\#]*?)                  # value up to the comment
         \s*\#\s*(?P<note>.+)$              # the marker comment
      """,
    re.X,
)

# A commented-out YAML line, e.g. '  # enableCluster: true # PROD: ...'
YAML_COMMENT = re.compile(r"^(?P<indent>\s*)\#\s?(?P<body>.*)$")
# An active YAML mapping key, used to track where in the tree we are.
YAML_KEY = re.compile(r"^(?P<indent>\s*)(?P<key>[A-Za-z_][\w.-]*):\s*(?P<rest>.*)$")


def has_value(value):
    """Whether a commented setting actually carries a value to activate.

    `# TYK_GW_HOSTNAME= # PROD: Set to a domain name` and `value: ""` state the
    recommendation in prose only. Activating them would set the variable to
    empty, which is worse than leaving it alone.
    """
    return value.strip().strip('"').strip("'") != ""


def marker_profiles(text):
    """Which profiles a marker comment belongs to, or () if it is not a marker.

    A single comment can carry more than one family, e.g.
      # SECURITY: password inline and sslmode=disable. PROD: use sslmode=require
    Returning only the first match hid such settings from whichever profile lost
    the race -- and for the line above that meant a credential was invisible to
    `--profile security`. Collect every family that matches.
    """
    found = []
    for with_colon, caps_only, profiles in MARKERS:
        if with_colon.search(text) or caps_only.search(text):
            for prof in profiles:
                if prof not in found:
                    found.append(prof)
    return tuple(found)


class Finding:
    """One annotated setting, and where it came from."""

    def __init__(self, path, line, profiles, key, value, advice, kind, active, block=None):
        self.path = path
        self.line = line
        self.profiles = profiles
        self.key = key
        self.value = value
        self.advice = advice
        self.kind = kind          # 'env' | 'yaml' | 'openshift'
        self.active = active      # already in effect, vs only suggested
        self.block = block or []  # raw dedented lines, for yaml/openshift grafting
        self.parent = []          # yaml path this block belongs under

    @property
    def where(self):
        return f"{self.path}:{self.line}"


# --------------------------------------------------------------------------
# env files
# --------------------------------------------------------------------------

def scan_env(path, lines):
    out = []
    for n, raw in enumerate(lines, 1):
        line = raw.rstrip("\n")
        m = ENV_LINE.match(line.strip())
        if not m:
            continue
        profiles = marker_profiles(m.group("note"))
        if not profiles:
            continue
        key, value = m.group("key"), m.group("val").strip()
        # '&&' shows up where one comment covers two related keys, so there is no
        # single assignment to emit. An empty value carries no recommendation
        # either -- the advice lives in the prose ("Set to a domain name"), and
        # emitting `KEY=` would actively blank the setting. Both stay advisory.
        advisory = "&&" in line.split("#")[-1] or "&&" in value or not has_value(value)
        out.append(Finding(
            path=path, line=n, profiles=profiles, key=key, value=value,
            advice=m.group("note").strip(),
            kind="env",
            active=m.group("off") is None,
            block=[] if advisory else [f"{key}={value}"],
        ))
    return out


# --------------------------------------------------------------------------
# yaml files
# --------------------------------------------------------------------------

def yaml_path_at(stack, indent):
    """The active-YAML key path enclosing something at this indent."""
    return [k for ind, k in stack if ind < indent]


def scan_yaml(path, lines):
    out = []
    stack = []          # [(indent, key)] of active mapping keys
    i = 0
    while i < len(lines):
        raw = lines[i].rstrip("\n")
        stripped = raw.strip()

        # Track the active document structure so commented blocks can be placed.
        if stripped and not stripped.startswith("#"):
            m = YAML_KEY.match(raw)
            if m:
                indent = len(m.group("indent"))
                while stack and stack[-1][0] >= indent:
                    stack.pop()
                stack.append((indent, m.group("key")))
                # An ACTIVE line can carry a marker too, e.g.
                #   enableDetailedRecording: true # PROD: Set to false
                # Missing these made `audit` silently blind to roughly a third of
                # the guidance in every Helm values file.
                profiles = marker_profiles(raw)
                if profiles:
                    f = classify(path, lines, i, raw.strip(), profiles, commented=False)
                    if f:
                        f.parent = yaml_path_at(stack[:-1], indent)
                        out.append(f)
            i += 1
            continue

        cm = YAML_COMMENT.match(raw)
        if not cm:
            i += 1
            continue
        indent, body = len(cm.group("indent")), cm.group("body")

        # An OpenShift banner opens a block of commented config to graft whole.
        if OPENSHIFT_BANNER.search(body):
            start = i
            i += 1
            # skip the closing '----' rule of the banner
            while i < len(lines):
                b = YAML_COMMENT.match(lines[i].rstrip("\n"))
                if b and set(b.group("body").strip()) <= {"-", " "} and b.group("body").strip():
                    i += 1
                    continue
                break
            block = []
            while i < len(lines):
                b = YAML_COMMENT.match(lines[i].rstrip("\n"))
                if not b:
                    break
                text = b.group("body")
                if not text.strip() or set(text.strip()) <= {"-"}:
                    break
                if OPENSHIFT_BANNER.search(text):
                    break
                block.append((len(b.group("indent")), text))
                i += 1
            if block:
                base = min(ind for ind, _ in block)
                f = Finding(
                    path=path, line=start + 1, profiles=("openshift",),
                    key=block[0][1].split(":")[0].strip(),
                    value="", advice="Required for deploying on RedHat OpenShift",
                    kind="openshift", active=False,
                    block=[" " * (ind - base) + t for ind, t in block],
                )
                f.parent = yaml_path_at(stack, min(ind for ind, _ in block) or indent)
                out.append(f)
            continue

        profiles = marker_profiles(body)
        if not profiles:
            i += 1
            continue

        f = classify(path, lines, i, body, profiles, commented=True)
        if f:
            f.parent = yaml_path_at(stack, indent)
            out.append(f)
        i += 1
    return out


def advice_of(body):
    """The marker comment at the end of a line."""
    best = None
    for with_colon, caps_only, _ in MARKERS:
        for pattern in (with_colon, caps_only):
            m = pattern.search(body)
            if m and (best is None or m.start() < best):
                best = m.start()
    return body[best:].strip() if best is not None else body.strip()


def preceding_name(lines, at, commented):
    """Nearest '- name: KEY' above a 'value:' line, in the same comment state."""
    for k in range(at - 1, max(-1, at - 4), -1):
        raw = lines[k].rstrip("\n")
        cm = YAML_COMMENT.match(raw)
        if commented:
            if not cm:
                return None
            text = cm.group("body")
        else:
            if cm:
                return None
            text = raw
        text = text.strip()
        if text.startswith("- name:"):
            return text.split("- name:")[1].strip().split()[0]
        if not text.startswith("value:"):
            return None
    return None


def classify(path, lines, i, body, profiles, commented):
    """Turn a marker-bearing line into a Finding, or None if it names no setting.

    Only a currently-commented setting carries a usable value, so only those get a
    `block` and can be activated by `apply`. Advice attached to a setting that is
    already active, or floating above one, is reported by `audit` but never
    auto-applied: its recommendation lives in prose, not in a value.
    """
    decl = re.split(r"\s+\#", body.strip())[0].rstrip()
    km = YAML_KEY.match(decl)
    advice = advice_of(body)

    # A bare advice line such as '# PROD: Keep false ...' names no setting itself;
    # it describes the next active line below it.
    if not km or marker_profiles(km.group("key") + ":"):
        for k in range(i + 1, min(len(lines), i + 4)):
            nxt = lines[k].rstrip("\n")
            if not nxt.strip() or YAML_COMMENT.match(nxt):
                continue
            nm = YAML_KEY.match(nxt)
            if nm:
                return Finding(path=path, line=i + 1, profiles=profiles,
                               key=nm.group("key"),
                               value=nm.group("rest").split("#")[0].strip(),
                               advice=advice, kind="yaml", active=True)
            break
        # Nothing below it to attach to. Do NOT drop it: one such line is the
        # control-API isolation guidance, which names two keys
        # ("TYK_GW_CONTROLAPIPORT and TYK_GW_CONTROLAPIHOSTNAME") so parses as
        # neither, and the skill is required to always report that one.
        names = re.findall(r"\b(TYK_[A-Z0-9_]+|PORTAL_[A-Z0-9_]+)\b", decl)
        return Finding(path=path, line=i + 1, profiles=profiles,
                       key=" and ".join(names) if names else "(see the line)",
                       value="", advice=advice, kind="yaml", active=False)

    value = km.group("rest").split("#")[0].strip()
    usable = commented and has_value(value)

    # 'value: "false"' belongs to the '- name: KEY' entry above it.
    if km.group("key") == "value":
        name = preceding_name(lines, i, commented)
        if not name:
            return None
        block = [f"- name: {name}", f"  {decl.strip()}"] if usable else []
        return Finding(path=path, line=i + 1, profiles=profiles, key=name,
                       value=value, advice=advice, kind="yaml",
                       active=not commented, block=block)

    return Finding(path=path, line=i + 1, profiles=profiles, key=km.group("key"),
                   value=value, advice=advice, kind="yaml", active=not commented,
                   block=[decl.strip()] if usable else [])


# --------------------------------------------------------------------------

def scan(path):
    with open(path, encoding="utf-8") as fh:
        lines = fh.readlines()
    if path.endswith((".yaml", ".yml")):
        return scan_yaml(path, lines)
    if path.endswith(".env") or os.path.basename(path).startswith(".env"):
        return scan_env(path, lines)
    # tolerate anything else that looks like KEY=value
    return scan_env(path, lines)


def wanted(findings, profiles):
    if not profiles:
        return findings
    return [f for f in findings if set(f.profiles) & set(profiles)]


# --------------------------------------------------------------------------
# output
# --------------------------------------------------------------------------

def cmd_list(args):
    for path in args.files:
        found = scan(path)
        counts = {}
        for f in found:
            for p in f.profiles:
                counts[p] = counts.get(p, 0) + 1
        # Print every profile including zeros. Omitting a profile made "no
        # security markers in this file" indistinguishable from "no security
        # problems", which is the opposite of the truth on the Helm paths.
        summary = ", ".join(f"{p}={counts.get(p, 0)}" for p in ALL_PROFILES)
        print(f"{path}: {summary}")
        missing = [p for p in ALL_PROFILES if not counts.get(p)]
        if missing:
            print(f"    note: no {', '.join(missing)} markers in this file. That means the file"
                  f" is not annotated for {'them' if len(missing) > 1 else 'it'},"
                  " NOT that there is nothing to fix -- see hardening.md.")
    return 0


# Values that are actually credentials must never be printed -- AGENTS.md forbids
# it, and `audit` is routinely piped into a log or a chat transcript.
#
# Match on the END of the key, not any substring, and never on profile membership.
# Both were wrong before: "security in profiles" masked `allowInsecureConfigs`,
# the one value hardening.md says to always flag, and a substring match masked
# `TYK_DB_SECURITY_USERPASSWORDMAXDAYS` -- a day count whose value of 0 means the
# policy is OFF, which is exactly what the reader needs to see.
SENSITIVE_NAME = re.compile(
    r"(SECRET|PASSWORD|PASSPHRASE|TOKEN|APIKEY|API_KEY|LICEN[SC]E|LICEN[SC]EKEY"
    r"|CONNECTIONSTRING|CONNECTION_STRING|RPCKEY|PRIVATEKEY|PRIVATE_KEY)$", re.I)


def is_sensitive(finding):
    """Whether this finding's VALUE is a credential and must not be printed."""
    return bool(SENSITIVE_NAME.search(finding.key))


def cmd_audit(args):
    total = 0
    for path in args.files:
        found = wanted(scan(path), args.profile)
        if not found:
            continue
        print(f"\n{path}")
        for f in found:
            state = "set" if f.active else "not set"
            shown = ""
            if f.active and f.value:
                shown = " = <not shown>" if is_sensitive(f) else f" = {f.value}"
            print(f"  [{'/'.join(f.profiles)}] {f.key}")
            print(f"      currently: {state}{shown}")
            print(f"      guidance : {f.advice}")
            print(f"      source   : {f.where}")
            total += 1
    print(f"\n{total} annotated setting(s)"
          + (f" for profile(s) {', '.join(args.profile)}" if args.profile else ""))
    return 0


def graft(tree, path, lines):
    node = tree
    for key in path:
        node = node.setdefault(key, {})
    node.setdefault("__lines__", []).extend(lines)


def emit(tree, indent=0, out=None):
    out = out if out is not None else []
    for key, node in tree.items():
        if key == "__lines__":
            for line in node:
                out.append(" " * indent + line)
            continue
        out.append(" " * indent + f"{key}:")
        emit(node, indent + 2, out)
    return out


# Only the OpenShift blocks carry a genuine "uncomment this to use it"
# recommendation, and they graft as new mappings the base file does not define.
# Everything else is unsafe to generate; see the refusal message below.
APPLIABLE = {"openshift"}


def cmd_apply(args):
    if not args.profile:
        print("apply needs at least one --profile", file=sys.stderr)
        return 2
    unsafe = sorted(set(args.profile) - APPLIABLE)
    if unsafe:
        print(f"""apply refuses --profile {', '.join(unsafe)}. Use `audit` and edit by hand.

Two reasons, both found by generating an overlay and then checking the result:

1. A commented-out setting does NOT reliably carry the recommended value. Many are
   the current default shown for illustration, so activating them emits the
   opposite of their own advice -- e.g.
     # TYK_GW_ENABLESEPERATEANALYTICSSTORE=false # PROD/PERFORMANCE: Set to true ...
   would be applied as "false". Nothing in the file distinguishes an illustrative
   value from a recommended one, so a generator cannot tell them apart.

2. On Helm, an overlay REPLACES a list rather than merging it. An emitted
   `extraEnvs` therefore deletes every entry the base file set -- 23 variables in
   kubernetes/helm-self-managed, including the Dashboard security block and the
   Portal CSRF setting. `helm template` still exits 0, so the usual validation
   does not catch it.

What to do instead:
  profiles.py audit {' '.join(args.files)} {' '.join('--profile ' + p for p in args.profile)}
then edit a copy of the values file in place, keeping its existing lists intact.

--profile openshift is still generated: those blocks are real recommendations and
graft as new mappings, so neither problem applies.""", file=sys.stderr)
        return 2
    path = args.files[0]
    found = wanted(scan(path), args.profile)
    applicable = [f for f in found if f.block]
    skipped = [f for f in found if not f.block]

    header = [
        f"# Generated by profiles.py from {os.path.basename(path)}",
        f"# Profiles: {', '.join(args.profile)}",
        "#",
        "# Every value below is a recommendation this repository already carries as a",
        "# marker comment. Review before use; the source of each is cited inline.",
        "",
    ]

    # `apply` only ever activates commented-out recommendations, and a credential is
    # never one of those -- but guard anyway so a future marker cannot leak one.
    applicable = [f for f in applicable if not is_sensitive(f)]
    withheld = [f for f in found if f.block and is_sensitive(f)]

    if path.endswith((".yaml", ".yml")):
        tree = {}
        for f in applicable:
            graft(tree, f.parent, [f"{l}  # {f.where}" if i == 0 else l
                                   for i, l in enumerate(f.block)])
        body = emit(tree)
    else:
        body = [f"{l}  # {f.where}" for f in applicable for l in f.block]

    text = "\n".join(header + body) + "\n"
    if args.output:
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(text)
        print(f"wrote {args.output}: {len(applicable)} setting(s) from {path}")
    else:
        sys.stdout.write(text)

    if skipped:
        print(f"\n# {len(skipped)} advisory-only marker(s) need a human decision:",
              file=sys.stderr)
        for f in skipped:
            print(f"#   {f.where}  {f.key}: {f.advice}", file=sys.stderr)
    if withheld:
        print(f"\n# {len(withheld)} credential(s) withheld from the overlay - set these yourself:",
              file=sys.stderr)
        for f in withheld:
            print(f"#   {f.where}  {f.key}", file=sys.stderr)
    return 0


def main():
    ap = argparse.ArgumentParser(
        description="Read Tyk deployment guidance out of this repository's config files.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name, fn in (("list", cmd_list), ("audit", cmd_audit), ("apply", cmd_apply)):
        p = sub.add_parser(name)
        p.add_argument("files", nargs="+")
        p.add_argument("--profile", action="append", default=[], choices=ALL_PROFILES)
        if name == "apply":
            p.add_argument("-o", "--output")
        p.set_defaults(fn=fn)
    args = ap.parse_args()
    missing = [f for f in args.files if not os.path.isfile(f)]
    if missing:
        print(f"no such file: {', '.join(missing)}", file=sys.stderr)
        return 2
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
