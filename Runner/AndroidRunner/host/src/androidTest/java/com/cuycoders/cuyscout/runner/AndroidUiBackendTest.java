package com.cuycoders.cuyscout.runner;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Intent;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.UiDevice;
import com.cuycoders.cuyscout.BridgeExecutor;
import com.cuycoders.cuyscout.UiNode;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;

/** Uses actual AccessibilityNodeInfo snapshots, not Android API stubs. */
@RunWith(AndroidJUnit4.class)
public final class AndroidUiBackendTest {
    @Test public void hintsRemainLabelsWithoutBecomingEditableValues() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        String app = instrumentation.getTargetContext().getPackageName();
        Activity activity = instrumentation.startActivitySync(new Intent(Intent.ACTION_MAIN)
            .setClassName(app, app + ".HostActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        try {
            instrumentation.runOnMainSync(() -> {
                LinearLayout layout = new LinearLayout(activity);
                layout.setOrientation(LinearLayout.VERTICAL);
                layout.setPadding(24, 120, 24, 24);
                TextView text = new TextView(activity);
                text.setHint("Read-only hint");
                layout.addView(text);
                EditText field = new EditText(activity);
                field.setHint("Editable hint");
                layout.addView(field);
                activity.setContentView(layout);
            });
            UiDevice.getInstance(instrumentation).waitForIdle();
            AndroidUiBackend backend = new AndroidUiBackend(instrumentation, app);
            UiNode field = null;
            boolean visibleHint = false;
            for (UiNode node : backend.snapshot()) {
                if (node.type.equals("statictext") && node.label.equals("Read-only hint")) visibleHint = true;
                if (node.type.equals("textfield") && node.label.equals("Editable hint")) field = node;
            }
            assertTrue("A read-only TextView hint is visible text", visibleHint);
            assertNotNull("An EditText hint remains a semantic label", field);
            assertEquals("An EditText placeholder is not its value", "", field.value);
            JSONObject result = new BridgeExecutor(backend).execute(new JSONObject().put("id", "hint-test")
                .put("action", new JSONObject().put("type", "typeElement").put("text", "demo")
                    .put("selector", new JSONObject().put("strategy", "label").put("value", "Editable hint"))));
            assertTrue("Typing by hint must succeed", result.getBoolean("success"));
            for (UiNode node : backend.snapshot()) {
                if (node.type.equals("textfield")) {
                    assertEquals("Typing must not append the placeholder", "demo", node.value);
                    return;
                }
            }
            fail("Editable field missing after typing");
        } finally {
            instrumentation.runOnMainSync(activity::finish);
        }
    }
}
