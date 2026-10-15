package com.cuycoders.cuyscout;

import org.json.JSONObject;
import java.util.Locale;

/** Immutable accessibility snapshot. Frames and all public gestures use density-independent dp. */
public final class UiNode {
    public final String key, parent, className, resourceId, type, identifier, label, value;
    public final double x, y, width, height;
    public final boolean enabled, visible, hittable, selected, editable, focused, systemAlert, interactive;
    public UiNode(String key, String parent, String className, String resourceId, String description, String text,
                  boolean enabled, boolean visible, boolean hittable, boolean selected, boolean editable,
                  boolean focused, boolean password, boolean clickable, boolean checkable, boolean systemAlert,
                  double x, double y, double width, double height) {
        this.key = key; this.parent = parent; this.className = className; this.resourceId = resourceId;
        this.type = role(className, editable, password, clickable, checkable);
        this.identifier = identifier(resourceId);
        this.label = description.isEmpty() ? (editable ? "" : text) : description;
        this.value = editable ? text : checkable ? Boolean.toString(selected) : "";
        this.enabled = enabled; this.visible = visible; this.hittable = hittable; this.selected = selected;
        this.editable = editable; this.focused = focused; this.systemAlert = systemAlert;
        this.interactive = editable || clickable || checkable || type.equals("slider");
        this.x = x; this.y = y; this.width = width; this.height = height;
    }
    public static String identifier(String raw) { int at = raw.indexOf(":id/"); return at >= 0 ? raw.substring(at + 4) : raw; }
    public static String role(String className, boolean editable, boolean password, boolean clickable, boolean checkable) {
        String name = className.toLowerCase(Locale.ROOT);
        if (editable || name.endsWith("edittext")) return password ? "securetextfield" : "textfield";
        if (checkable || name.endsWith("switch") || name.endsWith("checkbox") || name.endsWith("radiobutton")) return "switch";
        if (name.endsWith("seekbar")) return "slider";
        if (name.endsWith("button") || clickable) return "button";
        if (name.endsWith("textview")) return "statictext";
        if (name.endsWith("imageview")) return "image";
        if (name.endsWith("scrollview") || name.endsWith("recyclerview")) return "scrollview";
        return "other";
    }
    public JSONObject frame() { return new JSONObject().put("x", x).put("y", y).put("width", width).put("height", height); }
    public JSONObject json(boolean withHittable) {
        JSONObject json = new JSONObject().put("type", type).put("identifier", identifier).put("label", label)
            .put("value", value).put("enabled", enabled).put("exists", true).put("frame", frame());
        if (withHittable) json.put("hittable", hittable);
        return json;
    }
}
