#!/usr/bin/env ruby
# Derives CURRENT_PROJECT_VERSION (the iOS build number) using the same
# YYMMDDID CalVer encoding as notes-android's fastlane/common.Fastfile
# (parseVersionCode/generateVersionCode), so the fleet shares one
# convention instead of each app inventing its own.
#
# CFBundleVersion allows at most 3 dot-separated integer components, so
# unlike MARKETING_VERSION (CFBundleShortVersionString, YY.M.D) the ID
# segment can't be a 4th dot component here. Encoding it as a single
# integer keeps it within that limit (a bare integer is 1 component)
# while still being strictly increasing and losslessly decodable.
#
# Usage: ruby scripts/generate_build_number.rb [YY MM DD ID]
# With no arguments, uses today's date and id 0.

VERSION_CODE_OFFSET = 400_000_000
DATE_MULTIPLIER = 1000

def generate_build_number(year:, month:, day:, id:)
  date = year * 10_000 + month * 100 + day
  VERSION_CODE_OFFSET + date * DATE_MULTIPLIER + id
end

def parse_build_number(build_number)
  date_and_id = build_number - VERSION_CODE_OFFSET
  id = date_and_id % DATE_MULTIPLIER
  date = date_and_id / DATE_MULTIPLIER
  { year: date / 10_000, month: (date / 100) % 100, day: date % 100, id: id }
end

if __FILE__ == $PROGRAM_NAME
  today = Time.now
  year = ARGV[0] ? ARGV[0].to_i : today.year % 100
  month = ARGV[1] ? ARGV[1].to_i : today.month
  day = ARGV[2] ? ARGV[2].to_i : today.day
  id = ARGV[3] ? ARGV[3].to_i : 0

  puts generate_build_number(year: year, month: month, day: day, id: id)
end
