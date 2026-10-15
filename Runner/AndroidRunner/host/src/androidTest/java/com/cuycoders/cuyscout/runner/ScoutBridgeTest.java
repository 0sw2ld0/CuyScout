package com.cuycoders.cuyscout.runner;

import android.app.Instrumentation;
import android.content.Intent;
import android.os.*;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import com.cuycoders.cuyscout.*;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import java.io.*;
import java.nio.charset.StandardCharsets;

@RunWith(AndroidJUnit4.class)
public final class ScoutBridgeTest {
    @Test public void runBridge() {
        try { runConfiguredBridge(); }
        catch (Exception failed) { throw new AssertionError("Android bridge failed (" + failed.getClass().getSimpleName() + "); verify config, installed app, gateway connectivity and token"); }
    }
    private void runConfiguredBridge() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        String path = InstrumentationRegistry.getArguments().getString("cuyscoutConfig", "");
        if (!path.matches("/data/local/tmp/cuyscout-[a-zA-Z0-9-]+\\.json")) throw new IllegalArgumentException("Falta cuyscoutConfig válido");
        JSONObject config;
        // UiAutomation tokenizes commands without a shell: quotes become literal path
        // characters. The strict allowlist above makes this unquoted path safe.
        try (InputStream input = new ParcelFileDescriptor.AutoCloseInputStream(instrumentation.getUiAutomation().executeShellCommand("cat " + path))) {
            ByteArrayOutputStream data = new ByteArrayOutputStream(); byte[] bytes = new byte[4096]; int count;
            while ((count = input.read(bytes)) >= 0) { if (data.size() + count > 65536) throw new IOException("Config demasiado grande"); data.write(bytes, 0, count); }
            config = new JSONObject(data.toString("UTF-8"));
        } finally {
            try (InputStream cleanup = new ParcelFileDescriptor.AutoCloseInputStream(instrumentation.getUiAutomation().executeShellCommand("rm -f " + path))) {
                while (cleanup.read() != -1) { /* Wait for cleanup before entering the loop. */ }
            }
        }
        String app = config.getString("bundleId");
        Intent launch = instrumentation.getTargetContext().getPackageManager().getLaunchIntentForPackage(app);
        String activity = config.optString("appActivity", "");
        if (!activity.isEmpty()) {
            if (activity.startsWith(".")) activity = app + activity;
            launch = new Intent(Intent.ACTION_MAIN).setClassName(app, activity);
        }
        if (launch == null) throw new IllegalArgumentException("No hay actividad launcher para la app; verifica el package instalado");
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        boolean preserve = config.optBoolean("preserveRunningApp", false);
        if (preserve) launch.addFlags(Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
        if (!preserve || !app.equals(androidx.test.uiautomator.UiDevice.getInstance(instrumentation).getCurrentPackageName())) {
            instrumentation.getTargetContext().startActivity(launch);
        }
        BridgeExecutor executor = new BridgeExecutor(new AndroidUiBackend(instrumentation, app));
        BridgeLoop loop = new BridgeLoop(new BridgeLoop.HTTP(config.getString("url"), config.optString("token", "")), executor, config.getString("sessionId"));
        loop.run(config.optLong("maxSeconds", 600));
    }
}
