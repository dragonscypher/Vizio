package com.example.vizio

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val LM_CHANNEL = "lm_channel"
    private val VR_CHANNEL = "vr_channel"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LM_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "generateDescription") {
                val input = call.argument<String>("input") ?: ""
                val description = runInference(input)
                result.success(description)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isVrSupported" -> result.success(isVrSupported())
                "enterVrMode" -> result.success(enterVrMode())
                "getVrCapabilities" -> result.success(getVrCapabilities())
                "getEyeGazePoint" -> result.success(getEyeGazePoint())
                else -> result.notImplemented()
            }
        }
    }

    private fun runInference(input: String): String {
        val snippet = if (input.length > 50) input.substring(0, 50) + "..." else input
        return "Native LM: $snippet"
    }

    private fun isVrSupported(): Boolean {
        val pm = applicationContext.packageManager
        val hasVrFeature = pm.hasSystemFeature(PackageManager.FEATURE_VR_MODE_HIGH_PERFORMANCE)
        val hasOculusShell = try {
            pm.getPackageInfo("com.oculus.vrshell", 0)
            true
        } catch (e: Exception) {
            false
        }
        return hasVrFeature || hasOculusShell
    }

    private fun enterVrMode(): Boolean {
        if (!isVrSupported()) return false

        val pm = applicationContext.packageManager
        val shellIntent = pm.getLaunchIntentForPackage("com.oculus.vrshell")
        if (shellIntent != null) {
            shellIntent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(shellIntent)
            return true
        }
        return false
    }

    private fun getVrCapabilities(): Map<String, Boolean> {
        val vrSupported = isVrSupported()
        val metaDevice = isMetaDevice()
        val eyeTrackingSupported = isEyeTrackingFeatureAvailable()
        return mapOf(
            "vrSupported" to vrSupported,
            "metaDevice" to metaDevice,
            "eyeTrackingSupported" to eyeTrackingSupported,
        )
    }

    private fun getEyeGazePoint(): Map<String, Double>? {
        // Returning null means no live gaze coordinates are currently available.
        // Flutter side falls back to pointer-controlled focus when null.
        return null
    }

    private fun isMetaDevice(): Boolean {
        val maker = android.os.Build.MANUFACTURER.lowercase(Locale.US)
        val brand = android.os.Build.BRAND.lowercase(Locale.US)
        val model = android.os.Build.MODEL.lowercase(Locale.US)
        if (maker.contains("meta") || maker.contains("oculus")) return true
        if (brand.contains("meta") || brand.contains("oculus")) return true
        if (model.contains("quest") || model.contains("oculus")) return true

        val pm = applicationContext.packageManager
        val hasOculusRuntime = try {
            pm.getPackageInfo("com.oculus.systemdriver", 0)
            true
        } catch (e: Exception) {
            false
        }
        val hasOculusShell = try {
            pm.getPackageInfo("com.oculus.vrshell", 0)
            true
        } catch (e: Exception) {
            false
        }
        return hasOculusRuntime || hasOculusShell
    }

    private fun isEyeTrackingFeatureAvailable(): Boolean {
        val pm = applicationContext.packageManager
        val features = pm.systemAvailableFeatures ?: return false
        return features.any {
            val n = it.name?.lowercase(Locale.US) ?: return@any false
            n.contains("eye_tracking") || n.contains("eyetracking") || n.contains("gaze")
        }
    }
}
