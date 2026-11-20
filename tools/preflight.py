#!/usr/bin/env python3
"""
Check whether this machine can run a given Tyk deployment, before anything starts.

    preflight.py --platform docker
    preflight.py --platform helm --namespace tyk
    preflight.py --platform baremetal
    preflight.py --platform docker --ports 8080,3000,3001,6379,5432
    preflight.py --platform helm --licence TYK_LICENSE_KEY --env-file ./.env

Every failure is reported with the command that fixes it. Exits non-zero when a
required check fails, so it can gate a deployment.

Licence handling: this only ever reports whether a variable is PRESENT and
non-empty. It never prints, logs, or returns a licence value.

Deliberately dependency-free so it runs in whatever environment the agent is given.
"""
import argparse
import os
import shutil
import socket
import subprocess
import sys

# tool -> (version argv, why it is needed, how to install it on macOS / Linux)
TOOLS = {
    "docker": (["docker", "--version"], "run containers",
               "https://docs.docker.com/get-docker/"),
    "docker compose": (["docker", "compose", "version"], "run the Compose stacks",
                       "ships with Docker Desktop; on Linux install the docker-compose-plugin package"),
    "helm": (["helm", "version", "--short"], "install the Tyk charts",
             "brew install helm  |  https://helm.sh/docs/intro/install/"),
    "kubectl": (["kubectl", "version", "--client=true", "-o=json"], "talk to the cluster",
                "brew install kubectl  |  https://kubernetes.io/docs/tasks/tools/"),
    "oc": (["oc", "version", "--client"], "create OpenShift Routes",
           "https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html"),
    "curl": (["curl", "--version"], "verify endpoints", "preinstalled on macOS and most Linux"),
    "jq": (["jq", "--version"], "read JSON from the Tyk APIs", "brew install jq  |  apt-get install jq"),
    "hurl": (["hurl", "--version"], "run docker/getting-started's bootstrap",
             "brew install hurl  |  https://hurl.dev/docs/installation.html"),
    "openssl": (["openssl", "version"], "generate certificates and secrets",
                "preinstalled on macOS and most Linux"),
    "git": (["git", "--version"], "track your own overlays", "brew install git"),
}

# platform -> (required tools, optional tools)
PLATFORMS = {
    "docker":    (["docker", "docker compose", "curl"], ["jq", "openssl", "hurl", "git"]),
    "helm":      (["helm", "kubectl", "curl"], ["jq", "openssl", "git"]),
    "openshift": (["helm", "kubectl", "oc", "curl"], ["jq", "openssl", "git"]),
    "baremetal": (["curl"], ["jq", "openssl", "git"]),
}

DEFAULT_PORTS = {
    "docker": [8080, 3000, 3001, 6379, 5432],
    "helm": [],
    "openshift": [],
    "baremetal": [8080, 3000, 6379, 5432],
}

OK, WARN, FAIL = "ok", "warn", "FAIL"


class Report:
    def __init__(self):
        self.rows = []

    def add(self, status, what, detail="", fix=""):
        self.rows.append((status, what, detail, fix))

    @property
    def failed(self):
        return [r for r in self.rows if r[0] == FAIL]

    def render(self):
        width = max((len(r[1]) for r in self.rows), default=0)
        for status, what, detail, fix in self.rows:
            mark = {OK: "  ok  ", WARN: "  --  ", FAIL: "  FAIL"}[status]
            line = f"{mark} {what.ljust(width)}"
            if detail:
                line += f"  {detail}"
            print(line)
            if fix and status != OK:
                print(f"         fix: {fix}")
        bad, warned = len(self.failed), len([r for r in self.rows if r[0] == WARN])
        print(f"\n{len(self.rows) - bad - warned}/{len(self.rows)} checks passed"
              + (f", {warned} optional missing" if warned else "")
              + (f", {bad} blocking" if bad else ""))


def run(argv):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return None
    if p.returncode != 0:
        return None
    text = (p.stdout or p.stderr).strip()
    if not text:
        return ""
    # kubectl only reports a one-line version via structured output.
    if argv[0] == "kubectl" and text.startswith("{"):
        import json
        try:
            return json.loads(text)["clientVersion"]["gitVersion"]
        except (ValueError, KeyError):
            return text.splitlines()[0]
    return text.splitlines()[0]


def check_tools(report, platform):
    required, optional = PLATFORMS[platform]
    for name in required + optional:
        argv, why, fix = TOOLS[name]
        blocking = name in required
        if shutil.which(argv[0]) is None:
            report.add(FAIL if blocking else WARN, name,
                       f"not installed - needed to {why}", fix)
            continue
        version = run(argv)
        if version is None:
            report.add(FAIL if blocking else WARN, name,
                       f"installed but not usable - needed to {why}", fix)
        else:
            report.add(OK, name, version[:72])


def check_docker_daemon(report):
    if shutil.which("docker") is None:
        return
    info = run(["docker", "info", "--format", "{{.ServerVersion}}"])
    if info is None:
        report.add(FAIL, "docker daemon", "not responding",
                   "start Docker Desktop, or `sudo systemctl start docker`")
        return
    report.add(OK, "docker daemon", f"server {info}")
    ctx = run(["docker", "context", "show"])
    if ctx:
        report.add(OK, "docker context", f"{ctx}  <- deploying here")


def check_kube(report, namespace):
    if shutil.which("kubectl") is None:
        return
    ctx = run(["kubectl", "config", "current-context"])
    if ctx is None:
        report.add(FAIL, "kube context", "no current context",
                   "kubectl config use-context <name>")
        return
    report.add(OK, "kube context", f"{ctx}  <- deploying here")
    if run(["kubectl", "cluster-info"]) is None:
        report.add(FAIL, "cluster reachable", "cannot reach the API server",
                   "check your kubeconfig, VPN, and that the cluster is running")
        return
    report.add(OK, "cluster reachable", "API server responding")
    if namespace:
        exists = run(["kubectl", "get", "namespace", namespace, "-o", "name"]) is not None
        if exists:
            report.add(WARN, f"namespace {namespace}", "already exists",
                       "confirm with the user before deploying into an existing namespace")
        else:
            report.add(OK, f"namespace {namespace}", "does not exist yet, will be created")


def check_ports(report, ports):
    for port in ports:
        taken = False
        for family, addr in ((socket.AF_INET, ("127.0.0.1", port)),):
            with socket.socket(family, socket.SOCK_STREAM) as s:
                s.settimeout(0.4)
                taken = s.connect_ex(addr) == 0
        if taken:
            report.add(FAIL, f"port {port}", "already in use",
                       f"stop what is listening (`lsof -i :{port}`), or change the host port mapping")
        else:
            report.add(OK, f"port {port}", "free")


def ports_from_target(target):
    """Host ports a specific deployment directory binds, from its .env.example.

    The platform-wide defaults are the union of every topology's ports, so they
    report a Dashboard or Postgres you are not deploying as a blocker.
    """
    example = os.path.join(target, ".env.example")
    if not os.path.isfile(example):
        return None
    ports = []
    with open(example, encoding="utf-8") as fh:
        for line in fh:
            line = line.split("#")[0].strip()
            if not line or "=" not in line:
                continue
            key, _, value = line.partition("=")
            if key.strip().endswith("_PORT") and value.strip().isdigit():
                ports.append(int(value.strip()))
    return sorted(set(ports))


def check_licences(report, names, env_file):
    """Presence only. A licence value is never read into the report."""
    from_file = set()
    if env_file:
        if not os.path.isfile(env_file):
            report.add(FAIL, f"env file {env_file}", "not found",
                       "cp .env.example .env, then fill in the licence values")
            return
        with open(env_file, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line.startswith("#") or "=" not in line:
                    continue
                key, _, value = line.partition("=")
                if value.strip():
                    from_file.add(key.strip())
    for name in names:
        present = bool(os.environ.get(name, "").strip()) or name in from_file
        if present:
            report.add(OK, name, "set (value not shown)")
        else:
            report.add(FAIL, name, "missing or empty",
                       f"add {name}=<your licence> to {env_file or 'the .env file'} "
                       "- never commit it")


def main():
    ap = argparse.ArgumentParser(description="Preflight checks for a Tyk deployment.")
    ap.add_argument("--platform", required=True, choices=sorted(PLATFORMS))
    ap.add_argument("--namespace", help="Kubernetes namespace the deployment will use")
    ap.add_argument("--ports", help="comma-separated host ports to check (default: per platform)")
    ap.add_argument("--target", metavar="DIR",
                    help="deployment directory, e.g. docker/oss. Ports are read from its "
                         ".env.example so only the ports THIS topology binds are checked. "
                         "Without it, the platform-wide union is checked and unrelated "
                         "services will look like blockers.")
    ap.add_argument("--licence", action="append", default=[], metavar="VAR",
                    help="licence variable that must be present; repeatable")
    ap.add_argument("--env-file", help="also look for licence variables in this file")
    args = ap.parse_args()

    report = Report()
    check_tools(report, args.platform)
    if args.platform == "docker":
        check_docker_daemon(report)
    if args.platform in ("helm", "openshift"):
        check_kube(report, args.namespace)

    if args.ports:
        ports = [int(p) for p in args.ports.split(",") if p.strip()]
    elif args.target:
        ports = ports_from_target(args.target)
        if ports is None:
            # Not a blocker. Some rows have no .env.example at all -- for example
            # docker/getting-started, which layers its compose over
            # ../self-managed/ via start.sh. Declaring that a failure invented a
            # false blocker on a bundled-tested row, which is exactly what
            # --target exists to prevent.
            if not os.path.isdir(args.target):
                report.add(FAIL, f"target {args.target}", "no such directory",
                           "check the path against the topology matrix")
            else:
                report.add(WARN, f"target {args.target}",
                           "declares no host ports (no .env.example)",
                           "nothing to check here; see that directory's README for how it starts")
            ports = []
    else:
        ports = DEFAULT_PORTS[args.platform]
    check_ports(report, ports)

    if args.licence:
        check_licences(report, args.licence, args.env_file)

    print(f"preflight: {args.platform}")
    report.render()

    if args.platform == "baremetal" and sys.platform == "darwin":
        print("\nnote: this is a macOS host. The bare-metal path needs a Linux host with systemd\n"
              "      and apt or yum; nothing here verifies the package install itself.")
    return 1 if report.failed else 0


if __name__ == "__main__":
    sys.exit(main())
