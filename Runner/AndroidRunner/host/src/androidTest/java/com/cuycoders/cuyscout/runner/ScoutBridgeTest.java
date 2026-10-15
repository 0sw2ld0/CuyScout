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
        catch (Exception failed) { throw new AssertionError("Android bridge failed; verify config, installed app, gateway connectivity and token"); }
    }
    private void runConfiguredBridge() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        String path = InstrumentationRegistry.getArguments().getString("cuyscoutConfig", "");
        if (!path.matches("/data/local/tmp/cuyscout-[a-zA-Z0-9-]+\\.json")) throw new IllegalArgumentException("Falta cuyscoutConfig válido");
        JSONObject config;
        try (ParcelFileDescriptor descriptor = instrumentation.getUiAutomation().executeShellCommand("cat '" + path + "'"); InputStream input = new ParcelFileDescriptor.AutoCloseInputStream(descriptor)) {
            ByteArrayOutputStream data = new ByteArrayOutputStream(); byte[] bytes = new byte[4096]; int count;
            while ((count = input.read(bytes)) >= 0) { if (data.size() + count > 65536) throw new IOException("Config demasiado grande"); data.write(bytes, 0, count); }
            config = new JSONObject(data.toString("UTF-8"));
        } finally { try (ParcelFileDescriptor ignored = instrumentation.getUiAutomation().executeShellCommand("rm -f '" + path + "'")) { /* No credentials remain on disk during the loop. */ } }
        String app = config.getString("bundleId");
        Intent launch = instrumentation.getTargetContext().getPackageManager().getLaunchIntentForPackage(app);
        if (launch == null) throw new IllegalArgumentException("No hay actividad launcher para la app; verifica el package instalado");
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        instrumentation.getTargetContext().startActivity(launch);
        BridgeExecutor executor = new BridgeExecutor(new AndroidUiBackend(instrumentation, app));
        BridgeLoop loop = new BridgeLoop(new BridgeLoop.HTTP(config.getString("url"), config.optString("token", "")), executor, config.getString("sessionId"));
        loop.run(config.optLong("maxSeconds", 600));
    }
}
