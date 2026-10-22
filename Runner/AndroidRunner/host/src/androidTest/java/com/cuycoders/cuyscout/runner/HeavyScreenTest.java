package com.cuycoders.cuyscout.runner;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Intent;
import android.os.SystemClock;
import android.view.ViewGroup;
import android.widget.*;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.UiDevice;
import com.cuycoders.cuyscout.UiNode;
import org.junit.Test;
import org.junit.runner.RunWith;
import java.util.List;
import static org.junit.Assert.*;

/** A React Native home screen nests every card several layouts deep and keeps carousels off screen: thousands
 *  of nodes. A snapshot of such a screen must stay well inside the 25 s command budget. */
@RunWith(AndroidJUnit4.class)
public final class HeavyScreenTest {
    @Test public void heavyScreenSnapshotIsFast() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        String app = instrumentation.getTargetContext().getPackageName();
        Activity activity = instrumentation.startActivitySync(new Intent(Intent.ACTION_MAIN)
            .setClassName(app, app + ".HostActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        try {
            instrumentation.runOnMainSync(() -> {
                ScrollView scroll = new ScrollView(activity);
                LinearLayout rows = new LinearLayout(activity); rows.setOrientation(LinearLayout.VERTICAL);
                for (int row = 0; row < 30; row++) {
                    HorizontalScrollView carousel = new HorizontalScrollView(activity);
                    LinearLayout cards = new LinearLayout(activity);
                    for (int card = 0; card < 12; card++) {
                        ViewGroup parent = cards;
                        for (int depth = 0; depth < 6; depth++) { FrameLayout wrapper = new FrameLayout(activity); parent.addView(wrapper); parent = wrapper; }
                        LinearLayout body = new LinearLayout(activity); body.setOrientation(LinearLayout.VERTICAL); body.setClickable(true); body.setOnClickListener(v -> {});
                        TextView title = new TextView(activity); title.setText("Tarjeta " + row + "-" + card); body.addView(title);
                        TextView amount = new TextView(activity); amount.setText("S/ " + (row * 12 + card) + ".00"); body.addView(amount);
                        body.setPadding(24, 24, 24, 24); parent.addView(body, new FrameLayout.LayoutParams(320, 200));
                    }
                    carousel.addView(cards); rows.addView(carousel);
                }
                scroll.addView(rows); activity.setContentView(scroll);
            });
            UiDevice.getInstance(instrumentation).waitForIdle();
            AndroidUiBackend backend = new AndroidUiBackend(instrumentation, app);
            long best = Long.MAX_VALUE; List<UiNode> nodes = null;
            for (int i = 0; i < 3; i++) {
                long start = SystemClock.uptimeMillis(); nodes = backend.snapshot(); best = Math.min(best, SystemClock.uptimeMillis() - start);
                SystemClock.sleep(100);
            }
            boolean labeled = false;
            for (UiNode node : nodes) if (node.type.equals("button") && node.label.equals("Tarjeta 0-0 S/ 0.00")) labeled = true;
            assertTrue("A card is named by its texts", labeled);
            // 30 carousels of 12 cards are 3,360 nodes; only the cards on screen are walked.
            assertTrue("Off-screen cards must not be walked: " + nodes.size() + " nodes", nodes.size() < 1500);
            assertTrue("Snapshot of " + nodes.size() + " nodes took " + best + " ms", best < 3000);
        } finally {
            instrumentation.runOnMainSync(activity::finish);
        }
    }
}
