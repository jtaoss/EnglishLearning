package dev.personal.englishlearning

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val queue = flutterEngine.dartExecutor.binaryMessenger.makeBackgroundTaskQueue()
        val store = NotionCredentialStore(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "english_learning/android_notion_credentials",
            io.flutter.plugin.common.StandardMethodCodec.INSTANCE, queue).setMethodCallHandler { call, result ->
            try {
                val namespace = call.argument<String>("test_namespace")
                when (call.method) {
                    "read" -> result.success(store.read(namespace))
                    "write" -> { store.write(call.argument<String>("value") ?: error("missing"), namespace); result.success(null) }
                    "delete" -> { store.delete(namespace); result.success(null) }
                    "package" -> result.success(packageName)
                    "test_inspect" -> result.success(store.inspectTest(namespace, call.argument<String>("probe") ?: error("missing")))
                    "test_corrupt" -> { store.corruptTest(namespace); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                // Never log exceptions: messages can contain input or provider details.
                result.error("secure_storage_unavailable", "Android secure storage unavailable", null)
            }
        }
    }
}
