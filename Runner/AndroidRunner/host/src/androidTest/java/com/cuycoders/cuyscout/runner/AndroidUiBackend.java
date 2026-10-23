package com.cuycoders.cuyscout.runner;

import android.accessibilityservice.AccessibilityServiceInfo;
import android.app.Instrumentation;
import android.content.*;
import android.graphics.*;
import android.os.*;
import android.view.accessibility.*;
import androidx.test.uiautomator.UiDevice;
import com.cuycoders.cuyscout.*;
import java.io.ByteArrayOutputStream;
import java.util.*;

final class AndroidUiBackend implements UiBackend {
    private final Instrumentation instrumentation;
    private final UiDevice device;
    private final String packageName;
    private final float density;
    private final Map<String, AccessibilityNodeInfo> handles = new HashMap<>();
    private List<UiNode> cached;
    private long capturedAt;
    private static final class Surface {
        final int layer, id, type; final boolean focused; final Region region = new Region();
        Surface(AccessibilityWindowInfo window) {
            layer = window.getLayer(); id = window.getId(); type = window.getType(); focused = window.isFocused();
            if (Build.VERSION.SDK_INT >= 30) window.getRegionInScreen(region);
            else { Rect rect = new Rect(); window.getBoundsInScreen(rect); region.set(rect); }
        }
    }
    private static final class Raw {
        AccessibilityNodeInfo info; String key, parent, pkg, text, desc, className, id; Rect bounds = new Rect(); Surface surface;
    }
    AndroidUiBackend(Instrumentation instrumentation, String packageName) {
        this.instrumentation = instrumentation; this.packageName = packageName;
        device = UiDevice.getInstance(instrumentation);
        density = instrumentation.getTargetContext().getResources().getDisplayMetrics().density;
        AccessibilityServiceInfo service = instrumentation.getUiAutomation().getServiceInfo();
        service.flags |= AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS | AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS | AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS;
        instrumentation.getUiAutomation().setServiceInfo(service);
    }
    private String text(CharSequence value) { return value == null ? "" : value.toString(); }
    private void collect(AccessibilityNodeInfo info, String key, String parent, Surface surface, List<Raw> all, int depth) throws BridgeFailure {
        if (info == null) return;
        if (all.size() >= 10000 || depth > 100) throw new BridgeFailure(9, "Árbol Android demasiado grande");
        Raw raw = new Raw(); raw.info = info; raw.key = key; raw.parent = parent; raw.surface = surface;
        raw.pkg = text(info.getPackageName());
        // Empty EditTexts expose their hint through getText(). It is a label, not
        // an existing value: appending it would write the placeholder into the app.
        raw.text = info.isEditable() && info.isShowingHintText() ? "" : text(info.getText());
        // React Native gives some views a content description of a single (no-break) space: it names nothing, and it
        // hid the placeholder of a password field («Ingresa tu clave»), which is the field's stable name.
        raw.desc = Selectors.normalize(text(info.getContentDescription()));
        if (raw.desc.isEmpty() && info.isEditable()) raw.desc = Selectors.normalize(text(info.getHintText()));
        if (raw.desc.isEmpty() && info.isEditable() && info.isShowingHintText()) raw.desc = Selectors.normalize(text(info.getText()));
        raw.className = text(info.getClassName()); raw.id = text(info.getViewIdResourceName()); info.getBoundsInScreen(raw.bounds);
        all.add(raw); handles.put(key, info);
        // Each child costs an IPC to the app. What Android does not show to the user (carousel cards and list rows
        // scrolled off screen, hidden views) can be neither tapped nor read, and on a React Native home it is most
        // of the tree: walking it made one snapshot take seconds and commands end in runner_busy.
        if (!info.isVisibleToUser()) return;
        for (int i = 0; i < info.getChildCount(); i++) collect(child(info, i), key + "/" + i, key, surface, all, depth + 1);
    }
    /** One IPC brings up to 50 descendants depth first, so most children are already cached when visited. */
    private static final int PREFETCH = Build.VERSION.SDK_INT >= 33 ? AccessibilityNodeInfo.FLAG_PREFETCH_DESCENDANTS_DEPTH_FIRST | AccessibilityNodeInfo.FLAG_PREFETCH_UNINTERRUPTIBLE : 0;
    private static AccessibilityNodeInfo child(AccessibilityNodeInfo info, int index) { return Build.VERSION.SDK_INT >= 33 ? info.getChild(index, PREFETCH) : info.getChild(index); }
    private static boolean actionable(AccessibilityNodeInfo info) { return info.isClickable() || info.isEditable() || info.isCheckable(); }
    /** A clickable container without text of its own is named by the texts inside it, as TalkBack reads it:
     *  a button whose title lives in a child TextView must not show up as an unlabeled button. */
    private static void inheritLabels(List<Raw> all) {
        for (int i = 0; i < all.size(); i++) {
            Raw raw = all.get(i);
            if (!raw.text.isEmpty() || !raw.desc.isEmpty() || !raw.info.isClickable() || raw.info.isEditable()) continue;
            StringBuilder label = new StringBuilder(); String prefix = raw.key + "/";
            for (int j = i + 1; j < all.size() && all.get(j).key.startsWith(prefix); j++) {
                Raw child = all.get(j);
                if (actionable(child.info) || !child.info.isVisibleToUser()) continue;
                String part = child.desc.isEmpty() ? child.text : child.desc;
                if (!part.isEmpty()) { if (label.length() > 0) label.append(' '); label.append(part); }
                if (label.length() > 200) break;
            }
            raw.desc = label.toString();
        }
    }
    private void invalidate() { for (AccessibilityNodeInfo node : handles.values()) node.recycle(); handles.clear(); cached = null; }
    @Override public List<UiNode> snapshot() throws Exception {
        if (cached != null && SystemClock.uptimeMillis() - capturedAt < 50) return cached;
        invalidate(); List<Raw> all = new ArrayList<>(); List<Surface> surfaces = new ArrayList<>();
        // Android 14 caches nodes in the UiAutomation connection and relies on accessibility events to expire
        // them. Apps that skip those events (seen with a loading screen replaced by an error page) left the
        // runner reporting the old screen, or nothing, until the session restarted.
        if (Build.VERSION.SDK_INT >= 34) instrumentation.getUiAutomation().clearCache();
        List<AccessibilityWindowInfo> windows = new ArrayList<>(instrumentation.getUiAutomation().getWindows());
        windows.sort(Comparator.comparingInt(AccessibilityWindowInfo::getLayer).thenComparingInt(AccessibilityWindowInfo::getId));
        try {
            for (AccessibilityWindowInfo window : windows) {
                Surface surface = new Surface(window); surfaces.add(surface);
                // The keyboard and unfocused windows of other apps (status and navigation bars) are dropped below:
                // walking them only cost time.
                if (surface.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD) continue;
                AccessibilityNodeInfo root = Build.VERSION.SDK_INT >= 33 ? window.getRoot(PREFETCH) : window.getRoot();
                if (root != null && !surface.focused && !text(root.getPackageName()).equals(packageName)) { root.recycle(); continue; }
                collect(root, "w" + window.getId(), null, surface, all, 0);
            }
            inheritLabels(all);
            int width = device.getDisplayWidth(), height = device.getDisplayHeight(); Rect screen = new Rect(0, 0, width, height);
            // Only these can hide a node: checking every later node against every node was quadratic in the tree.
            Map<String, Raw> byKey = new HashMap<>(); List<Integer> covering = new ArrayList<>();
            for (int i = 0; i < all.size(); i++) {
                Raw other = all.get(i); byKey.put(other.key, other);
                if (other.info.isVisibleToUser() && (actionable(other.info) || !other.text.isEmpty() || !other.desc.isEmpty() || other.className.endsWith("ImageView"))) covering.add(i);
            }
            List<UiNode> result = new ArrayList<>();
            for (int i = 0; i < all.size(); i++) {
                Raw raw = all.get(i); AccessibilityNodeInfo node = raw.info;
                if (raw.surface.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD) continue;
                boolean system = !raw.pkg.equals(packageName);
                if (system && (!raw.surface.focused || !(raw.pkg.endsWith(".permissioncontroller") || raw.pkg.endsWith(".packageinstaller") || raw.pkg.equals("android") || raw.pkg.equals("com.android.systemui")))) continue;
                int x = raw.bounds.centerX(), y = raw.bounds.centerY();
                boolean visible = node.isVisibleToUser() && !raw.bounds.isEmpty() && Rect.intersects(raw.bounds, screen);
                boolean hittable = visible && node.isEnabled() && x >= 0 && x < width && y >= 0 && y < height;
                for (Surface other : surfaces) if (other.layer > raw.surface.layer && other.region.contains(x, y)) hittable = false;
                int from = Collections.binarySearch(covering, i + 1); if (from < 0) from = -from - 1;
                for (int c = from; hittable && c < covering.size(); c++) {
                    Raw other = all.get(covering.get(c));
                    if (other.surface.id != raw.surface.id) continue;
                    if (Geometry.siblingCovers(raw.key, other.key, true, true, x, y, other.bounds.left, other.bounds.top, other.bounds.right, other.bounds.bottom)) hittable = false;
                }
                // A descendant clipped by its parent must not offer an off-parent center tap.
                for (Raw parent = raw.parent == null ? null : byKey.get(raw.parent); hittable && parent != null; parent = parent.parent == null ? null : byKey.get(parent.parent))
                    if (!parent.bounds.contains(x, y)) hittable = false;
                result.add(new UiNode(raw.key, raw.parent, raw.className, raw.id, raw.desc, raw.text, node.isEnabled(), visible, hittable,
                    node.isSelected() || node.isChecked(), node.isEditable(), node.isFocused(), node.isPassword(), node.isClickable(), node.isCheckable(), system,
                    Geometry.dp(raw.bounds.left, density), Geometry.dp(raw.bounds.top, density), Geometry.dp(raw.bounds.width(), density), Geometry.dp(raw.bounds.height(), density)));
            }
            cached = result; capturedAt = SystemClock.uptimeMillis(); return result;
        } finally { for (AccessibilityWindowInfo window : windows) window.recycle(); }
    }
    private int px(double dp) { return Geometry.px(dp, density); }
    @Override public void tap(double x, double y, int count, long duration) throws Exception {
        int xx = px(x), yy = px(y);
        if (xx < 0 || yy < 0 || xx >= device.getDisplayWidth() || yy >= device.getDisplayHeight()) throw new BridgeFailure(11, "Coordenada fuera de pantalla");
        for (int i = 0; i < count; i++) {
            boolean success = duration > 0 ? device.swipe(xx, yy, xx, yy, Math.max(1, (int)(duration / 5))) : device.click(xx, yy);
            if (!success) throw new BridgeFailure(11, "No se pudo tocar el elemento"); if (i + 1 < count) Thread.sleep(70);
        }
        invalidate();
    }
    private AccessibilityNodeInfo handle(UiNode node) throws BridgeFailure {
        AccessibilityNodeInfo info = handles.get(node.key); if (info == null || !info.refresh()) throw BridgeFailure.missing(); return info;
    }
    @Override public void setText(UiNode node, String text) throws Exception {
        AccessibilityNodeInfo info = handle(node); info.performAction(AccessibilityNodeInfo.ACTION_FOCUS);
        Bundle args = new Bundle(); args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text);
        if (!info.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) throw new BridgeFailure(10, "not_editable: el control no admite ACTION_SET_TEXT");
        boolean keyboard = false;
        for (AccessibilityWindowInfo window : instrumentation.getUiAutomation().getWindows()) {
            try { if (window.getType() == AccessibilityWindowInfo.TYPE_INPUT_METHOD && window.isActive()) keyboard = true; }
            finally { window.recycle(); }
        }
        if (keyboard) device.pressBack();
        invalidate();
    }
    @Override public void submit(UiNode node) throws Exception {
        AccessibilityNodeInfo info = handle(node);
        if (node.editable) {
            info.performAction(AccessibilityNodeInfo.ACTION_FOCUS);
            if (Build.VERSION.SDK_INT < 30 || !info.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.getId())) {
                if (!device.pressEnter()) throw new BridgeFailure(10, "No se pudo enviar el formulario");
            }
        } else tap(node.x + node.width / 2, node.y + node.height / 2, 1, 0);
        invalidate();
    }
    @Override public void scroll(double x, double y) throws Exception {
        int width = device.getDisplayWidth(), height = device.getDisplayHeight();
        int dx = px(x), dy = px(y);
        if (dx == 0 && dy == 0) dy = height / 2;
        int startX = width / 2, startY = height / 2;
        if (!device.swipe(startX, startY, Math.max(1, Math.min(width - 1, startX - dx)), Math.max(1, Math.min(height - 1, startY - dy)), 40)) throw new BridgeFailure(11, "No se pudo desplazar la pantalla");
        invalidate();
    }
    @Override public byte[] screenshot(UiNode crop) throws Exception {
        Bitmap bitmap = instrumentation.getUiAutomation().takeScreenshot(); if (bitmap == null) throw new BridgeFailure(9, "No se pudo capturar la pantalla");
        Bitmap image = bitmap;
        try {
            if (crop != null) {
                int left = Math.max(0, px(crop.x)), top = Math.max(0, px(crop.y));
                int right = Math.min(bitmap.getWidth(), px(crop.x + crop.width)), bottom = Math.min(bitmap.getHeight(), px(crop.y + crop.height));
                if (right <= left || bottom <= top) throw new BridgeFailure(11, "Elemento fuera de pantalla");
                image = Bitmap.createBitmap(bitmap, left, top, right - left, bottom - top);
            }
            ByteArrayOutputStream bytes = new ByteArrayOutputStream(); if (!image.compress(Bitmap.CompressFormat.PNG, 100, bytes)) throw new BridgeFailure(9, "No se pudo codificar PNG"); return bytes.toByteArray();
        } finally { if (image != bitmap) image.recycle(); bitmap.recycle(); }
    }
    @Override public void clipboard(String text) {
        if (Build.VERSION.SDK_INT >= 29) instrumentation.getUiAutomation().adoptShellPermissionIdentity();
        try { instrumentation.runOnMainSync(() -> ((ClipboardManager) instrumentation.getTargetContext().getSystemService(Context.CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("", text))); }
        finally { if (Build.VERSION.SDK_INT >= 29) instrumentation.getUiAutomation().dropShellPermissionIdentity(); }
    }
    @Override public String clipboard() {
        final String[] value = {""}; if (Build.VERSION.SDK_INT >= 29) instrumentation.getUiAutomation().adoptShellPermissionIdentity();
        try { instrumentation.runOnMainSync(() -> { ClipboardManager manager = (ClipboardManager) instrumentation.getTargetContext().getSystemService(Context.CLIPBOARD_SERVICE); ClipData data = manager.getPrimaryClip(); if (data != null && data.getItemCount() > 0) value[0] = data.getItemAt(0).coerceToText(instrumentation.getTargetContext()).toString(); }); }
        finally { if (Build.VERSION.SDK_INT >= 29) instrumentation.getUiAutomation().dropShellPermissionIdentity(); }
        return value[0];
    }
}
