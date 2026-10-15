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
        raw.pkg = text(info.getPackageName()); raw.text = text(info.getText()); raw.desc = text(info.getContentDescription());
        raw.className = text(info.getClassName()); raw.id = text(info.getViewIdResourceName()); info.getBoundsInScreen(raw.bounds);
        all.add(raw); handles.put(key, info);
        for (int i = 0; i < info.getChildCount(); i++) collect(info.getChild(i), key + "/" + i, key, surface, all, depth + 1);
    }
    private void invalidate() { for (AccessibilityNodeInfo node : handles.values()) node.recycle(); handles.clear(); cached = null; }
    @Override public List<UiNode> snapshot() throws Exception {
        if (cached != null && SystemClock.uptimeMillis() - capturedAt < 50) return cached;
        invalidate(); List<Raw> all = new ArrayList<>(); List<Surface> surfaces = new ArrayList<>();
        List<AccessibilityWindowInfo> windows = new ArrayList<>(instrumentation.getUiAutomation().getWindows());
        windows.sort(Comparator.comparingInt(AccessibilityWindowInfo::getLayer).thenComparingInt(AccessibilityWindowInfo::getId));
        try {
            for (AccessibilityWindowInfo window : windows) {
                Surface surface = new Surface(window); surfaces.add(surface);
                collect(window.getRoot(), "w" + window.getId(), null, surface, all, 0);
            }
            List<UiNode> result = new ArrayList<>();
            for (int i = 0; i < all.size(); i++) {
                Raw raw = all.get(i); AccessibilityNodeInfo node = raw.info;
                if (raw.surface.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD) continue;
                boolean system = !raw.pkg.equals(packageName);
                if (system && (!raw.surface.focused || !(raw.pkg.endsWith(".permissioncontroller") || raw.pkg.endsWith(".packageinstaller") || raw.pkg.equals("android") || raw.pkg.equals("com.android.systemui")))) continue;
                boolean visible = node.isVisibleToUser() && !raw.bounds.isEmpty() && Rect.intersects(raw.bounds, new Rect(0, 0, device.getDisplayWidth(), device.getDisplayHeight()));
                boolean hittable = visible && node.isEnabled() && raw.bounds.centerX() >= 0 && raw.bounds.centerX() < device.getDisplayWidth() && raw.bounds.centerY() >= 0 && raw.bounds.centerY() < device.getDisplayHeight();
                for (Surface other : surfaces) if (other.layer > raw.surface.layer && other.region.contains(raw.bounds.centerX(), raw.bounds.centerY())) hittable = false;
                for (int j = i + 1; hittable && j < all.size(); j++) {
                    Raw other = all.get(j);
                    if (other.surface.id != raw.surface.id) continue;
                    if (Geometry.siblingCovers(raw.key, other.key, other.info.isVisibleToUser(), other.info.isClickable() || other.info.isEditable() || other.info.isCheckable() || !other.text.isEmpty() || !other.desc.isEmpty() || other.className.endsWith("ImageView"), raw.bounds.centerX(), raw.bounds.centerY(), other.bounds.left, other.bounds.top, other.bounds.right, other.bounds.bottom)) hittable = false;
                }
                // A descendant clipped by its parent must not offer an off-parent center tap.
                String ancestor = raw.parent;
                while (hittable && ancestor != null) { AccessibilityNodeInfo parent = handles.get(ancestor); if (parent == null) break; Rect bounds = new Rect(); parent.getBoundsInScreen(bounds); if (!bounds.contains(raw.bounds.centerX(), raw.bounds.centerY())) hittable = false; int cut = ancestor.lastIndexOf('/'); ancestor = cut < 0 ? null : ancestor.substring(0, cut); }
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
