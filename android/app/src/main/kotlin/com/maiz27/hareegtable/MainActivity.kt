package com.maiz27.hareegtable

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val preferences = getSharedPreferences("hareeg_table", Context.MODE_PRIVATE)

        // Replay payloads are far too large for SharedPreferences, so they live
        // as files. `noBackupFilesDir` keeps them out of Android auto backup
        // without any manifest opt-out, matching the iOS backup exclusion.
        val replayDirectory = File(noBackupFilesDir, REPLAY_DIRECTORY_NAME)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hareeg_table/local_storage",
        ).setMethodCallHandler { call, result ->
            // `listFiles` is the only method with no key. Every other method
            // keeps the original "a storage key is required" guard.
            if (call.method == "listFiles") {
                handleListFiles(replayDirectory, result)
                return@setMethodCallHandler
            }

            val arguments = call.arguments as? Map<*, *>
            val key = arguments?.get("key") as? String

            if (key == null) {
                result.error("invalid_arguments", "A storage key is required.", null)
                return@setMethodCallHandler
            }

            when (call.method) {
                "getString" -> result.success(preferences.getString(key, null))
                "setString" -> {
                    val value = arguments["value"] as? String
                    if (value == null) {
                        result.error("invalid_arguments", "A string value is required.", null)
                    } else {
                        preferences.edit().putString(key, value).apply()
                        result.success(null)
                    }
                }
                "remove" -> {
                    preferences.edit().remove(key).apply()
                    result.success(null)
                }
                "writeFile" -> {
                    val value = arguments["value"] as? String
                    if (value == null) {
                        result.error("invalid_arguments", "A file payload is required.", null)
                    } else {
                        handleWriteFile(replayDirectory, key, value, result)
                    }
                }
                "readFile" -> handleReadFile(replayDirectory, key, result)
                "deleteFile" -> handleDeleteFile(replayDirectory, key, result)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Resolves the file a logical [key] maps to, or null when the key is not
     * usable.
     *
     * The Dart store validates keys too; this check is deliberately
     * independent, so a caller that reaches the channel directly still cannot
     * name a file outside [directory]. The canonical-parent comparison is a
     * second, structural guard that does not depend on the character rule
     * being complete.
     *
     * Canonicalization can fail for reasons that have nothing to do with the
     * key — a filesystem I/O error, for instance. That [IOException] is
     * allowed to propagate so the caller reports it as `io_error`: it is a
     * retryable backend failure, not a permanent verdict on the caller's key.
     * Collapsing it into null here would tell a caller its perfectly valid
     * match id was malformed.
     */
    @Throws(IOException::class)
    private fun resolveReplayFile(directory: File, key: String, suffix: String): File? {
        if (!KEY_PATTERN.matches(key)) {
            return null
        }

        val candidate = File(directory, key + suffix)
        return if (candidate.canonicalFile.parentFile != directory.canonicalFile) {
            null
        } else {
            candidate
        }
    }

    private fun invalidKey(key: String, result: MethodChannel.Result) {
        result.error(
            "invalid_key",
            "\"$key\" is not a valid replay file key.",
            null,
        )
    }

    private fun handleWriteFile(
        directory: File,
        key: String,
        value: String,
        result: MethodChannel.Result,
    ) {
        var staging: File? = null

        try {
            val target = resolveReplayFile(directory, key, REPLAY_EXTENSION)
            staging = resolveReplayFile(directory, key, STAGING_EXTENSION)
            if (target == null || staging == null) {
                invalidKey(key, result)
                return
            }

            if (!directory.isDirectory && !directory.mkdirs()) {
                result.error("io_error", "Could not create the replay directory.", null)
                return
            }

            staging.writeText(value, Charsets.UTF_8)

            // rename(2) replaces the target in one step, so the committed
            // payload is never deleted first. A failed replacement therefore
            // leaves the previous replay readable instead of destroying it.
            if (!staging.renameTo(target)) {
                staging.delete()
                result.error("io_error", "Could not commit the replay file.", null)
                return
            }

            result.success(null)
        } catch (error: IOException) {
            staging?.delete()
            result.error("io_error", error.message ?: "Replay file write failed.", null)
        } catch (error: SecurityException) {
            staging?.delete()
            result.error("io_error", error.message ?: "Replay file write was denied.", null)
        }
    }

    private fun handleReadFile(directory: File, key: String, result: MethodChannel.Result) {
        try {
            val file = resolveReplayFile(directory, key, REPLAY_EXTENSION)
            if (file == null) {
                invalidKey(key, result)
                return
            }

            if (!file.isFile) {
                // Absent is a normal answer, not a failure: callers self-heal a
                // missing replay and must be able to tell it from a real error.
                // A directory occupying the name is absent too — it is not a
                // replay payload.
                result.success(null)
                return
            }

            result.success(file.readText(Charsets.UTF_8))
        } catch (error: IOException) {
            result.error("io_error", error.message ?: "Replay file read failed.", null)
        } catch (error: SecurityException) {
            result.error("io_error", error.message ?: "Replay file read was denied.", null)
        }
    }

    private fun handleDeleteFile(directory: File, key: String, result: MethodChannel.Result) {
        try {
            val file = resolveReplayFile(directory, key, REPLAY_EXTENSION)
            if (file == null) {
                invalidKey(key, result)
                return
            }

            // `isFile` is what keeps a directory that merely occupies a replay
            // file name from being deleted as though it were a payload.
            if (!file.isFile) {
                result.success(false)
                return
            }

            if (file.delete()) {
                result.success(true)
            } else {
                result.error("io_error", "Could not delete the replay file.", null)
            }
        } catch (error: IOException) {
            result.error("io_error", error.message ?: "Replay file delete failed.", null)
        } catch (error: SecurityException) {
            result.error("io_error", error.message ?: "Replay file delete was denied.", null)
        }
    }

    /**
     * Lists logical replay keys.
     *
     * An entry is listed only when it is a regular file named `<key>.json` and
     * `<key>` satisfies [KEY_PATTERN]. That single rule is what skips
     * directories, `.json.tmp` staging leftovers, foreign extensions, and files
     * whose name cannot map back to a key a caller could pass in again.
     */
    private fun handleListFiles(directory: File, result: MethodChannel.Result) {
        try {
            if (!directory.isDirectory) {
                result.success(emptyList<String>())
                return
            }

            val entries = directory.listFiles()
            if (entries == null) {
                result.error("io_error", "Could not list the replay directory.", null)
                return
            }

            val keys = entries
                .filter { it.isFile && it.name.endsWith(REPLAY_EXTENSION) }
                .map { it.name.removeSuffix(REPLAY_EXTENSION) }
                .filter { KEY_PATTERN.matches(it) }
                .sorted()

            result.success(keys)
        } catch (error: SecurityException) {
            result.error("io_error", error.message ?: "Replay file listing was denied.", null)
        }
    }

    private companion object {
        const val REPLAY_DIRECTORY_NAME = "replays"
        const val REPLAY_EXTENSION = ".json"
        const val STAGING_EXTENSION = ".json.tmp"

        /**
         * Mirrors `replayFileKeyPattern` in `replay_file_store.dart`. Keys are
         * logical identifiers; nothing in this class ever accepts a path.
         */
        val KEY_PATTERN = Regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,119}$")
    }
}
