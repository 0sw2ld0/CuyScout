package com.cuycoders.cuyscout.host;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

/** Instrumentation target only; the bridge drives the application supplied in its config. */
public final class HostActivity extends Activity {
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        TextView text = new TextView(this);
        text.setText("CuyScout Android bridge");
        setContentView(text);
    }
}
