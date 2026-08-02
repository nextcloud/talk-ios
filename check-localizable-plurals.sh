#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# check-localizable-plurals.sh
#
# Checks that localized strings are set up so they can actually be translated:
#
#   1. Every string taking a number has a plural rule in Localizable.stringsdict.
#   2. Plural strings are read with String.localizedStringWithFormat, not
#      String(format:), which passes no locale and picks the wrong category.
#   3. No key is built with string interpolation, which makes it vary at runtime.
#   4. Every plural rule still corresponds to a string that exists.
#
# Run this after generate-localizable-strings-file.sh.

set -uo pipefail

# comm requires both of its inputs to be sorted in the same collation.
export LC_ALL=C

STRINGS="NextcloudTalk/en.lproj/Localizable.strings"
STRINGSDICT="NextcloudTalk/en.lproj/Localizable.stringsdict"

TAB=$'\t'

for file in "$STRINGS" "$STRINGSDICT"; do
  if [[ ! -f "$file" ]]; then
    echo "error: $file not found - run this from the repository root" >&2
    exit 2
  fi
done

# Strings that take a number but where no word agrees with it.
ALLOWED_WITHOUT_PLURAL=(
  'Add (%lu)'  # Parenthesised selection count on a button
  'Answer %ld' # Numbers an answer of a poll, it is not a count

  # Only used by the stable branch, which the generated file also covers.
  '%d replies'
  '%@, %@, %@ and %ld others will receive invitations'
)

# An integer conversion like %d, %ld or %4$ld. Deliberately not %@.
INTEGER_SPECIFIER='%([0-9]+\$)?l{0,2}[diu]([^a-zA-Z]|$)'

SOURCES=(--include=*.swift --include=*.m --include=*.h)
EXCLUDES=(--exclude-dir=ThirdParty --exclude-dir=Pods --exclude-dir=node_modules
          --exclude-dir=build --exclude-dir=DerivedData)

# Skip the stable branch clone, in case a previous generation run left it behind.
if [[ -r .tx/backport ]]; then
  EXCLUDES+=(--exclude-dir="$(<.tx/backport)")
fi

# .strings and source keys are escaped, stringsdict keys are not. Compare unescaped.
unescape() {
  sed -e 's|\\"|"|g' -e 's|\\\\|\\|g'
}

# Keys of Localizable.strings, i.e. the part before the " = " of each entry.
strings_keys() {
  grep -oE '^"([^"\\]|\\.)*" = ' "$STRINGS" | sed -E 's|^"(.*)" = $|\1|' | unescape
}

# Top level keys of the stringsdict, which are indented by exactly one tab.
stringsdict_keys() {
  grep -E "^$TAB<key>" "$STRINGSDICT" \
    | sed -E "s|^$TAB<key>(.*)</key>\$|\\1|" \
    | sed -e 's|&lt;|<|g' -e 's|&gt;|>|g' -e 's|&amp;|\&|g'
}

# A list for comm via <(...), without the empty line printf gives for an empty one.
list() {
  [[ -n "$1" ]] && printf '%s\n' "$1"
}

all_keys=$(strings_keys | sort -u)
plural_keys=$(stringsdict_keys | sort -u)
allowed_keys=$(printf '%s\n' "${ALLOWED_WITHOUT_PLURAL[@]}" | sort -u)

if [[ -z "$all_keys" || -z "$plural_keys" ]]; then
  echo "error: could not read any keys - the file format is not what this script expects" >&2
  exit 2
fi

missing=0
misread=0
interpolations=0

# 1. Strings taking a number that have no plural rule.
numeric_keys=$(list "$all_keys" | grep -E "$INTEGER_SPECIFIER")
missing_keys=$(comm -23 <(list "$numeric_keys") <(list "$plural_keys") \
  | comm -23 - <(list "$allowed_keys"))

while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  echo "error: \"$key\" takes a number but has no plural rule"
  grep -rlF -e "NSLocalizedString(\"$key\"" -e "NSLocalizedString(@\"$key\"" \
    "${SOURCES[@]}" "${EXCLUDES[@]}" . 2>/dev/null \
    | sed -E 's|^\./|       |' | sort -u
  missing=$((missing + 1))
done <<< "$missing_keys"

# 2. Plural strings read without a locale.
format_calls=$(grep -rnoE 'String\(format: *NSLocalizedString\(@?"([^"\\]|\\.)*"' \
  "${SOURCES[@]}" "${EXCLUDES[@]}" . 2>/dev/null | sed -E 's|^\./||')

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  location=${line%%:String(format:*}
  key=${line#*NSLocalizedString(}
  key=${key#@}
  key=${key#\"}
  key=${key%\"}
  key=$(printf '%s' "$key" | unescape)
  if grep -qxF "$key" <<< "$plural_keys"; then
    echo "error: $location"
    echo "       \"$key\" has a plural rule, so it must be read with"
    echo "       String.localizedStringWithFormat, not String(format:)"
    misread=$((misread + 1))
  fi
done <<< "$format_calls"

# 3. Keys built with string interpolation: at runtime the key contains the
# interpolated value, so the lookup always misses.
interpolated=$(grep -rnoE 'NSLocalizedString\(@?"[^"]*\\\(' \
  "${SOURCES[@]}" "${EXCLUDES[@]}" . 2>/dev/null | sed -E 's|^\./||')

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "error: ${line%%:NSLocalizedString*}"
  echo "       the key is built with string interpolation, so it varies at runtime"
  echo "       and never matches a translation - use a format specifier instead"
  interpolations=$((interpolations + 1))
done <<< "$interpolated"

# 4. Plural rules for strings that no longer exist.
while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  echo "warning: \"$key\" has a plural rule but is not in $(basename "$STRINGS")"
done <<< "$(comm -13 <(list "$all_keys") <(list "$plural_keys"))"

problems=$((missing + misread + interpolations))

if [[ $problems -eq 0 ]]; then
  echo "Plural check passed: $(list "$plural_keys" | wc -l | tr -d ' ') plural rules," \
       "$(list "$numeric_keys" | wc -l | tr -d ' ') strings taking a number"
  exit 0
fi

echo
echo "$problems problem(s) found."
if [[ $missing -gt 0 ]]; then
  echo "Add a plural rule to $STRINGSDICT, or list the string in"
  echo "ALLOWED_WITHOUT_PLURAL in $(basename "$0") if no word in it agrees with the number."
fi

exit 1
