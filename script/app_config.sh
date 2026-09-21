#!/usr/bin/env bash

# App identity is kept here so local builds, release builds, and install checks
# cannot silently drift to different bundle identifiers.
QUOTAMONITOR_APP_NAME="QuotaMonitor"
QUOTAMONITOR_BINARY_NAME="QuotaMonitor"
QUOTAMONITOR_BUNDLE_ID="com.cmsjcm.QuotaMonitorStatus4"
QUOTAMONITOR_PREVIOUS_BUNDLE_ID="com.cmsjcm.QuotaMonitorStatus3"
QUOTAMONITOR_VERSION="${QUOTAMONITOR_VERSION:-0.1.8}"
QUOTAMONITOR_BUILD_NUMBER="${QUOTAMONITOR_BUILD_NUMBER:-10}"
