#!/usr/bin/env bash
set -euo pipefail

app_name="Roblox Stats Bar.app"
build_dir=".build"
binary_dir="${build_dir}/release"
dist_dir="dist"
app_dir="${dist_dir}/${app_name}"
contents_dir="${app_dir}/Contents"
macos_dir="${contents_dir}/MacOS"

mkdir -p "${binary_dir}" "${macos_dir}"

swiftc -O \
  Sources/RobloxStatsBar/AppConfig.swift \
  Sources/RobloxStatsBar/ChromeCookieImporter.swift \
  Sources/RobloxStatsBar/CreatorHubScraper.swift \
  Sources/RobloxStatsBar/DashboardMetricsStore.swift \
  Sources/RobloxStatsBar/RobloxAPI.swift \
  Sources/RobloxStatsBar/main.swift \
  -framework Security \
  -lsqlite3 \
  -o "${binary_dir}/RobloxStatsBar"

rm -rf "${app_dir}"
mkdir -p "${macos_dir}" "${contents_dir}/Resources"

cp "${binary_dir}/RobloxStatsBar" "${macos_dir}/RobloxStatsBar"
cp "Resources/Info.plist" "${contents_dir}/Info.plist"
chmod +x "${macos_dir}/RobloxStatsBar"
codesign --force --deep --sign - "${app_dir}" >/dev/null

echo "Built ${app_dir}"
