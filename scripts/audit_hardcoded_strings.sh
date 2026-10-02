#!/usr/bin/env bash
#
# Audits Features/*, VikuDesignSystem, VikuWidgetKit, and the Viku app target
# for raw string literals that aren't going through a String Catalog yet (see
# docs/LOCALIZATION_PLAN.md). Counts Text(", Button(", Label(", and
# .navigationTitle(" call sites, per module.
#
# A call site is considered "already migrated" and excluded if it:
#   - passes `bundle: .module` (the String Catalog resolution the SPM
#     package gotcha requires, see LOCALIZATION_PLAN.md's Phase 0 writeup)
#   - uses `Text(verbatim:)` (deliberately unlocalized caller-supplied text,
#     see ARCHITECTURE.md §8)
#   - for the `Viku` app target only (no `bundle: .module` there — `Bundle.main`
#     is already correct): the literal's text is a key in
#     `Viku/Localizable.xcstrings`, checked via `check_catalog_membership.py`.
#
# Usage:
#   scripts/audit_hardcoded_strings.sh            # print counts per module
#   scripts/audit_hardcoded_strings.sh --verbose   # also list each match
#   scripts/audit_hardcoded_strings.sh --ci        # exit non-zero if any remain
#
# Intended to double as the Phase 5 CI guard once the count reaches zero.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

verbose=false
ci_mode=false
for arg in "$@"; do
    case "$arg" in
        --verbose) verbose=true ;;
        --ci) ci_mode=true ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [--verbose] [--ci]" >&2
            exit 2
            ;;
    esac
done

modules=(
    "Packages/Features/Onboarding"
    "Packages/Features/Home"
    "Packages/Features/Projects"
    "Packages/Features/Tasks"
    "Packages/Features/Settings"
    "Packages/Features/Calendar"
    "Packages/Features/Search"
    "Packages/VikuDesignSystem"
    "Packages/VikuWidgetKit"
    "Viku"
)

pattern='\b(Text|Button|Label)\("|\.navigationTitle\("'

total=0
printf '%-28s %s\n' "Module" "Raw literals"
printf '%-28s %s\n' "------" "------------"

for module in "${modules[@]}"; do
    # Swift packages keep their code under Sources/; the app target (Viku)
    # has no such subdirectory and is scanned at its own root instead.
    src_dir="$repo_root/$module/Sources"
    if [[ ! -d "$src_dir" ]]; then
        src_dir="$repo_root/$module"
    fi
    if [[ ! -d "$src_dir" ]]; then
        printf '%-28s %s\n' "$module" "(no Sources/ dir)"
        continue
    fi

    if [[ "$module" == "Viku" ]]; then
        matches="$(grep -rEn "$pattern" "$src_dir" --include='*.swift' \
            | grep -v 'Text(verbatim:' \
            | python3 "$repo_root/scripts/check_catalog_membership.py" "$repo_root/Viku/Localizable.xcstrings" \
            || true)"
    else
        matches="$(grep -rEn "$pattern" "$src_dir" --include='*.swift' \
            | grep -v 'bundle: \.module' \
            | grep -v 'Text(verbatim:' \
            || true)"
    fi

    count=0
    if [[ -n "$matches" ]]; then
        count="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"
    fi
    total=$((total + count))

    module_name="$(basename "$module")"
    printf '%-28s %s\n' "$module_name" "$count"

    if [[ "$verbose" == true && -n "$matches" ]]; then
        printf '%s\n' "$matches" | sed "s|^$repo_root/||; s|^|    |"
    fi
done

printf '%-28s %s\n' "------" "------------"
printf '%-28s %s\n' "TOTAL" "$total"

if [[ "$ci_mode" == true && "$total" -gt 0 ]]; then
    echo
    echo "error: $total hardcoded string literal(s) found outside the String Catalog mechanism." >&2
    echo "Run with --verbose to list them." >&2
    exit 1
fi
