# HandBrake (Unraid container) task runner — run `just` to list recipes.
# Recipes use sh (Git Bash on Windows). See CLAUDE.md for the full guide.
# This is a container repo: no Go, no Node app — the deliverable is the image.

set shell := ["sh", "-cu"]

# List available recipes
default:
    @just --list

# Build the image locally (same tag the CI gate uses)
build:
    docker build -t handbrake:smoke-amd64 .

# Build + boot the container locally (Ctrl-C to stop; WebUI on 3000/HTTP, 3001/HTTPS)
smoke: build
    docker run --rm -it --name hb-smoke -p 3000:3000 -p 3001:3001 handbrake:smoke-amd64

# End-to-end watch-folder test against a running `just smoke` container
convert-test:
    ffmpeg -v error -y -f lavfi -i testsrc=size=320x240:rate=15:duration=2 -c:v libx264 -pix_fmt yuv420p /tmp/hb-smoke.mkv
    docker cp /tmp/hb-smoke.mkv hb-smoke:/watch/hb-smoke.mkv
    docker exec hb-smoke chown abc:abc /watch/hb-smoke.mkv
    @echo "dropped /watch/hb-smoke.mkv — watch: docker logs -f hb-smoke"

# Lint the Dockerfile (same ignores as CI)
hadolint:
    hadolint Dockerfile --ignore DL3008 --ignore DL3009

# ShellCheck every shipped script (honor shebangs; no --shell override, like CI)
shellcheck:
    find rootfs -type f \( -name '*.sh' -o -name 'run' -o -name 'autostart' \) -print0 \
      | xargs -0 shellcheck -S warning -x -e SC1091

# Validate every XML file (Unraid template etc.)
xml:
    find . -name '*.xml' -not -path './.git/*' -print0 | xargs -0 -r xmllint --noout

# Reject CR characters in anything that ships into the Linux image
lf:
    ! grep -rlI "$(printf '\r')" rootfs .github/assets/banner-raw.txt .github/workflows

# Full pre-push chain: every lint CI runs
check: hadolint shellcheck xml lf
    @echo "All lint checks passed."

# Secret-scan the working tree
secrets:
    gitleaks dir . --redact --no-banner

# Re-record docs/handbrake-capabilities.md inputs from a built image
caps:
    docker run --rm --entrypoint sh handbrake:smoke-amd64 -c 'cat /usr/local/share/handbrake-version.txt'
    docker run --rm --entrypoint sh handbrake:smoke-amd64 -c "sed -n '/-e, --encoder/,/^[[:space:]]*-[a-zA-Z-]/p' /usr/local/share/handbrake-cli-help.txt"

# Regenerate the README banner pair
banner:
    node .github/assets/gen-banner.mjs

# Scaffold release notes for a version, e.g. `just notes 1.1.0`
notes version:
    printf '## ✨ Added\n\n## ⚡ Improved\n\n## 🐛 Fixed\n' > .github/release-notes/v{{version}}.md
    @echo "Wrote .github/release-notes/v{{version}}.md — edit it, then commit (NEVER tag without approval)."
