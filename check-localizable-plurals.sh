#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# check-localizable-plurals.sh
#
# Checks that localized strings taking a number are set up for plurals:
#
#   1. Every string in en.lproj/Localizable.strings with an integer format
#      specifier has a plural rule in en.lproj/Localizable.stringsdict.
#   2. Every string that has a plural rule is read with
#      String.localizedStringWithFormat and not with String(format:), which
#      passes no locale and therefore cannot pick the right plural category.
#   3. No localized string builds its key with string interpolation, which
#      makes the key vary at runtime so it never matches a translation.
#   4. Every plural rule still corresponds to a string that exists.
#
# Run this after generate-localizable-strings-file.sh, so that
# Localizable.strings is up to date.

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

# Strings that take a number but intentionally have no plural rule, because no
# word in them agrees with that number.
ALLOWED_WITHOUT_PLURAL=(
  'Add (%lu)'  # Parenthesised selection count on a button
  'Answer %ld' # Numbers an answer of a poll, it is not a count

  # Localizable.strings is generated from this branch and the stable branch
  # together, so it still contains strings that only the stable branch uses.
  # A plural rule added here would not reach that branch anyway.
  '%d replies'
  '%@, %@, %@ and %ld others will receive invitations'
)

# An integer conversion, optionally positional ("%4$ld") and optionally with a
# length modifier ("%ld", "%lld"). Deliberately does not match "%@".
INTEGER_SPECIFIER='%([0-9]+\$)?l{0,2}[diu]([^a-zA-Z]|$)'

SOURCES=(--include=*.swift --include=*.m --include=*.h)
EXCLUDES=(--exclude-dir=ThirdParty --exclude-dir=Pods --exclude-dir=node_modules
          --exclude-dir=build --exclude-dir=DerivedData)

# generate-localizable-strings-file.sh clones the stable branch into the
# repository root and removes it again. Skip it if it is still lying around.
if [[ -r .tx/backport ]]; then
  EXCLUDES+=(--exclude-dir="$(<.tx/backport)")
fi

# Source literals and .strings keys escape quotes and backslashes; the keys in
# the stringsdict are plain XML text. Compare them all in unescaped form.
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

# Writes a newline separated list, without the trailing empty line that
# printf would produce for an empty list. comm reads these via <(...).
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

# 3. Keys built with string interpolation. genstrings records the literal
# "\(foo)", but at runtime the key contains the interpolated value, so the
# lookup always misses and the string is never translated.
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
