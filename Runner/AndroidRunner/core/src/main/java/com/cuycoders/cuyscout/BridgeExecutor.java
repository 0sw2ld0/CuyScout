package com.cuycoders.cuyscout;

import org.json.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;

public final class BridgeExecutor {
    private final UiBackend ui;
    private final java.util.function.LongSupplier clock;
    private final long budgetNanos;
    private long deadline;
    public BridgeExecutor(UiBackend ui) { this(ui, System::nanoTime, 25_000); }
    public BridgeExecutor(UiBackend ui, java.util.function.LongSupplier clock, long budgetMs) {
        if (budgetMs < 1 || budgetMs > 29000) throw new IllegalArgumentException("Invalid command budget");
        this.ui = ui; this.clock = clock; this.budgetNanos = budgetMs * 1_000_000L;
    }
    public JSONObject execute(JSONObject command) {
        JSONObject result = new JSONObject().put("commandID", command.optString("id")).put("success", false);
        try {
            deadline = clock.getAsLong() + budgetNanos;
            byte[] payload = perform(command.getJSONObject("action"), 0);
            result.put("success", true);
            if (payload != null) result.put("payloadBase64", Base64.getEncoder().encodeToString(payload));
        } catch (BridgeFailure failure) { result.put("error", failure.getMessage()).put("errorCode", failure.code); }
        catch (Exception failure) { result.put("error", "No se pudo ejecutar el comando Android").put("errorCode", 9); }
        return result;
    }
    private byte[] json(JSONObject value) { return value.toString().getBytes(StandardCharsets.UTF_8); }
    private JSONObject value(Object value) { return new JSONObject().put("value", value == null ? JSONObject.NULL : value); }
    private UiNode resolve(List<UiNode> nodes, JSONObject selector, UiNode parent) throws Exception {
        List<UiNode> matches = Selectors.find(nodes, selector, parent);
        for (UiNode node : matches) if (node.hittable) return node;
        if (matches.isEmpty()) throw BridgeFailure.missing(); return matches.get(0);
    }
    private UiNode resolve(JSONObject action) throws Exception { return resolve(ui.snapshot(), action.optJSONObject("selector"), null); }
    private void touchable(UiNode node) throws BridgeFailure {
        if (!node.hittable || !node.enabled) throw new BridgeFailure(11, "not_visible: el elemento está oculto, tapado o deshabilitado");
    }
    private byte[] perform(JSONObject action, int depth) throws Exception {
        if (clock.getAsLong() >= deadline) throw new BridgeFailure(9, "Tiempo de comando agotado; vuelve a observar antes de actuar");
        if (depth > 16) throw new BridgeFailure(9, "Secuencia demasiado profunda");
        String type = action.getString("type");
        switch (type) {
            case "findElement": return json(new JSONObject().put("element", resolve(action).json(false)));
            case "findElements": return json(new JSONObject().put("elements", array(Selectors.find(ui.snapshot(), action.optJSONObject("selector"), null), false)));
            case "findElementFromElement": case "findElementsFromElement": {
                List<UiNode> nodes = ui.snapshot(); UiNode parent = resolve(nodes, action.optJSONObject("parent"), null);
                List<UiNode> matches = Selectors.find(nodes, action.optJSONObject("child"), parent);
                if (type.equals("findElementsFromElement")) return json(new JSONObject().put("elements", array(matches, false)));
                if (matches.isEmpty()) throw BridgeFailure.missing(); return json(new JSONObject().put("element", matches.get(0).json(false)));
            }
            case "tapElement": case "doubleTap": case "longPress": {
                UiNode node = resolve(action); touchable(node);
                long hold = type.equals("longPress") ? duration(action.optDouble("duration", 1)) : 0;
                if (hold * 1_000_000L >= deadline - clock.getAsLong()) throw new BridgeFailure(9, "Duración superior al tiempo restante del comando");
                ui.tap(node.x + node.width / 2, node.y + node.height / 2, type.equals("doubleTap") ? 2 : 1, hold); return null;
            }
            case "typeElement": case "clearElement": {
                UiNode node = resolve(action); touchable(node);
                if (!node.editable) throw new BridgeFailure(10, "not_editable: usa un campo de texto");
                ui.setText(node, type.equals("clearElement") ? "" : node.value + action.getString("text")); return null;
            }
            case "type": {
                for (UiNode node : ui.snapshot()) if (node.focused && node.editable) {
                    touchable(node); ui.setText(node, node.value + action.getString("text")); return null;
                }
                throw new BridgeFailure(10, "not_editable: enfoca primero un campo de texto");
            }
            case "submit": { UiNode node = resolve(action); touchable(node); ui.submit(node); return null; }
            case "elementAttribute": case "elementProperty": {
                UiNode node = resolve(action); String name = action.getString("name");
                switch (name) {
                    case "label": return json(value(node.label)); case "value": return json(value(node.value));
                    case "identifier": return json(value(node.identifier)); case "enabled": return json(value(node.enabled));
                    case "exists": return json(value(true)); default: return json(value(null));
                }
            }
            case "elementDisplayed": return json(value(resolve(action).hittable));
            case "elementEnabled": return json(value(resolve(action).enabled));
            case "elementSelected": return json(value(resolve(action).selected));
            case "elementName": return json(value(resolve(action).label));
            case "elementRect": return json(value(resolve(action).frame()));
            case "elementScreenshot": return ui.screenshot(resolve(action));
            case "waitFor": {
                double timeout = action.optDouble("timeout", 10);
                if (!Double.isFinite(timeout) || timeout < 0 || timeout > 25) throw new BridgeFailure(9, "waitFor admite entre 0 y 25 segundos");
                long waitDeadline = Math.min(deadline, clock.getAsLong() + (long) (timeout * 1e9));
                do {
                    if (!Selectors.find(ui.snapshot(), action.optJSONObject("selector"), null).isEmpty()) return null;
                    if (clock.getAsLong() >= waitDeadline) break; Thread.sleep(100);
                } while (true);
                throw BridgeFailure.missing();
            }
            case "assertVisible": {
                UiNode node = resolve(action); if (!node.visible || !node.hittable) throw new BridgeFailure(11, "not_visible: el elemento no está visible"); return null;
            }
            case "assertText": {
                UiNode node = resolve(action); String actual = node.editable || node.label.isEmpty() ? node.value : node.label;
                if (!actual.equals(action.getString("expected"))) throw new BridgeFailure(6, "El texto no coincide con el esperado"); return null;
            }
            case "accessibilityTree": case "accessibilityTreeWithOptions": case "accessibilityDiff": return json(tree(ui.snapshot(), action.optJSONObject("options")));
            case "tap": ui.tap(number(action, "x"), number(action, "y"), 1, 0); return null;
            case "scroll": ui.scroll(number(action, "x"), number(action, "y")); return null;
            case "screenshot": return ui.screenshot(null);
            case "screenStatic": {
                MessageDigest hash = MessageDigest.getInstance("SHA-256"); byte[] first = hash.digest(ui.screenshot(null));
                Thread.sleep(200); return json(new JSONObject().put("static", Arrays.equals(first, hash.digest(ui.screenshot(null)))));
            }
            case "setClipboard": ui.clipboard(action.getString("text")); return null;
            case "getClipboard": return json(value(ui.clipboard()));
            case "sequence": {
                JSONArray actions = action.getJSONArray("actions"); if (actions.length() > 100) throw new BridgeFailure(9, "Secuencia demasiado larga");
                for (int i = 0; i < actions.length(); i++) perform(actions.getJSONObject(i), depth + 1); return null;
            }
            default: throw BridgeFailure.unsupported();
        }
    }
    private static double number(JSONObject action, String key) throws Exception {
        double value = action.getDouble(key); if (!Double.isFinite(value)) throw new BridgeFailure(9, "Coordenada inválida"); return value;
    }
    private static long duration(double seconds) throws BridgeFailure {
        if (!Double.isFinite(seconds) || seconds < 0 || seconds > 10) throw new BridgeFailure(9, "Duración fuera de rango"); return (long)(seconds * 1000);
    }
    private static JSONArray array(List<UiNode> nodes, boolean hittable) {
        JSONArray result = new JSONArray(); for (UiNode node : nodes) result.put(node.json(hittable)); return result;
    }
    public static JSONObject tree(List<UiNode> nodes, JSONObject supplied) throws BridgeFailure {
        JSONObject options = supplied == null ? new JSONObject() : supplied;
        boolean visible = options.optBoolean("visibleOnly", false), interactive = options.optBoolean("interactiveOnly", false);
        boolean hittable = options.optBoolean("hittableOnly", false), system = options.optBoolean("includeSystemAlerts", false);
        int max = options.optInt("maxElements", 10000); if (max < 0 || max > 10000) throw new BridgeFailure(9, "maxElements fuera de rango");
        List<UiNode> filtered = new ArrayList<>(); Set<String> alertTexts = new LinkedHashSet<>(), buttons = new LinkedHashSet<>();
        for (UiNode node : nodes) {
            if (system && node.systemAlert && node.visible) { if (!node.label.isEmpty()) alertTexts.add(node.label); if (node.interactive && !node.label.isEmpty()) buttons.add(node.label); }
            if (node.systemAlert && !system || visible && !node.visible || interactive && !node.interactive || hittable && !node.hittable) continue;
            if (node.identifier.isEmpty() && node.label.isEmpty() && node.value.isEmpty() && !node.interactive) continue;
            if (filtered.size() < max) filtered.add(node);
        }
        JSONObject result = new JSONObject().put("count", filtered.size()).put("elements", array(filtered, hittable));
        if (!alertTexts.isEmpty()) result.put("activeAlert", new JSONObject().put("text", String.join(" ", alertTexts)).put("buttons", new JSONArray(buttons)));
        return result;
    }
}
