import os

/// Diagnostics of the app model: triggers, queries and the schedule. Never
/// shown in the UI.
nonisolated let appLog = Logger(subsystem: "xyz.chrismetz.pacemark", category: "app")
