# Contributing

Thanks for taking the time to contribute. This project is part of the NexusPlatform portfolio and follows a deliberately strict bar — the goal is that every merged change leaves the repo more professional than it arrived.

## Ground rules

1. **Every non-trivial decision gets an ADR.** If you are introducing a new dependency, swapping a component, or changing a public interface, add a Markdown file in `docs/adr/NNNN-<slug>.md`. Use the existing ADRs as a template.
2. **CI is the gate.** A PR merges only when `make validate`, `make smoke` (on a runner-sized stack), CodeQL, and Trivy all pass.
3. **Pin versions.** No floating tags (`:latest`, `:stable`). All image references use explicit semver tags, bumped by Dependabot or a human PR.
4. **Dashboards-as-code.** Grafana dashboards live as JSON in `compose/grafana/dashboards/` and are loaded via provisioning. UI-edited dashboards must be exported and committed before merge.
5. **Secure-by-default.** Any new host port must bind to `127.0.0.1`. Any new secret must be documented in `.env.example` with a safe default.

## Development loop

### POSIX shells (Linux / macOS / WSL2 / Git Bash)

```bash
git checkout -b feat/<short-slug>
make up
# ...edit...
make validate
make smoke
git commit -m "feat(otel): add JMX receiver for Kafka"
```

### Windows PowerShell 7+

```powershell
git checkout -b feat/<short-slug>
.\run.ps1 up
# ...edit...
.\run.ps1 validate
.\run.ps1 smoke
git commit -m "feat(otel): add JMX receiver for Kafka"
```

Both paths must pass locally before pushing. CI re-runs `validate` + `smoke` on Linux.

## Cross-platform rules

The repo is expected to work identically on Linux, macOS, WSL2, and Windows 11 native. When adding scripts or files, keep these in mind:

- **Shell scripts (`*.sh`)** — target `bash` / POSIX. Always add a matching verb in `run.ps1` if the script is part of the developer contract.
- **PowerShell scripts (`*.ps1`)** — target PowerShell 7+. Use `$ErrorActionPreference = 'Stop'`. Avoid aliases (`%`, `?`, `ls`) — use full cmdlet names.
- **Line endings** — enforced by `.gitattributes`. `*.sh` is LF; `*.ps1` is CRLF; YAML/JSON/Markdown/SQL is LF. Don't override.
- **Paths in docs** — when both platforms are involved, show both (POSIX `make foo` / PowerShell `.\run.ps1 foo`).

## Commit convention

We use [Conventional Commits](https://www.conventionalcommits.org/). Common prefixes:

- `feat:` — user-visible addition
- `fix:` — bug fix
- `docs:` — documentation only
- `refactor:` — internal change with no behavior delta
- `chore:` — tooling, deps, ci

## Reporting issues

Open a GitHub issue with: expected behavior, actual behavior, `docker compose version`, OS, and the output of `make health`.

## Code of conduct

Be respectful. Assume good faith. Keep technical criticism technical.
