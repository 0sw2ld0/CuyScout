package com.cuycoders.cuyscout;

import org.json.*;
import org.junit.Test;
import static org.junit.Assert.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public class BridgeContractTest {
    private static UiNode node(String key, String parent, String role, String id, String description, String text, boolean hit) {
        return new UiNode(key, parent, role, id, description, text, true, hit, hit, false, role.endsWith("EditText"), false, false, role.endsWith("Button"), false, false, 24, 100, 120, 48);
    }
    static class Backend implements UiBackend {
        List<UiNode> nodes = new ArrayList<>(Arrays.asList(
            node("root", null, "android.view.ViewGroup", "", "", "", true),
            node("root/title", "root", "android.widget.TextView", "", "", "Demo Wallet", true),
            node("root/field", "root", "android.widget.EditText", "com.example.wallet:id/email", "Email", "", true),
            node("root/button", "root", "android.widget.Button", "com.example.wallet:id/login", "", "Login", true),
            node("hidden", null, "android.widget.Button", "hidden", "Hidden", "", false)));
        int taps, snapshots, writes, submits, scrolls, screenshots;
        String lastText = "", clipboard = ""; double tapX, tapY; long duration; UiNode crop;
        @Override public List<UiNode> snapshot() { snapshots++; return nodes; }
        @Override public void tap(double x, double y, int count, long duration) { taps += count; tapX = x; tapY = y; this.duration = duration; }
        @Override public void setText(UiNode node, String text) { writes++; lastText = text; }
        @Override public void submit(UiNode node) { submits++; }
        @Override public void scroll(double x, double y) { scrolls++; }
        @Override public byte[] screenshot(UiNode crop) { screenshots++; this.crop = crop; return new byte[]{(byte)0x89, 0, (byte)255, 13, 10}; }
        @Override public void clipboard(String text) { clipboard = text; }
        @Override public String clipboard() { return clipboard; }
    }
    private final Backend ui = new Backend();
    private final BridgeExecutor executor = new BridgeExecutor(ui);
    private JSONObject selector(String strategy, String value) { return new JSONObject().put("strategy", strategy).put("value", value); }
    private JSONObject action(String type) { return new JSONObject().put("type", type); }
    private JSONObject button(String type) { return action(type).put("selector", selector("accessibilityIdentifier", "login")); }
    private JSONObject field(String type) { return action(type).put("selector", selector("accessibilityIdentifier", "email")); }
    private JSONObject run(JSONObject action) { return executor.execute(new JSONObject().put("id", "command-1").put("action", action)); }
    private JSONObject payload(JSONObject result) { assertTrue(result.toString(), result.getBoolean("success")); return new JSONObject(new String(Base64.getDecoder().decode(result.getString("payloadBase64")), StandardCharsets.UTF_8)); }
    private void failure(int code, JSONObject action) { JSONObject result = run(action); assertFalse(result.getBoolean("success")); assertEquals(code, result.getInt("errorCode")); assertEquals("command-1", result.getString("commandID")); }

    @Test public void identifierAndLabelNormalization() {
        UiNode button = ui.nodes.get(3); assertEquals("login", button.identifier); assertEquals("Login", button.label); assertEquals("", button.value);
        assertEquals("custom_tag", UiNode.identifier("custom_tag"));
        assertEquals("switch", UiNode.role("android.widget.CheckBox", false, false, false, true));
        assertEquals("securetextfield", UiNode.role("android.widget.EditText", true, true, true, false));
        assertEquals("image", UiNode.role("android.widget.ImageView", false, false, false, false));
        assertEquals("button", UiNode.role("android.view.View", false, false, true, false));
    }
    @Test public void findUsesResourceIDWithOrWithoutPackage() {
        assertEquals("login", payload(run(button("findElement"))).getJSONObject("element").getString("identifier"));
        assertEquals("login", payload(run(action("findElement").put("selector", selector("accessibilityIdentifier", "com.example.wallet:id/login")))).getJSONObject("element").getString("identifier"));
    }
    @Test public void semanticStrategiesResolveWithoutFullTreeExport() {
        for (JSONObject selector : Arrays.asList(selector("label", "Login"), selector("type", "button"), selector("type", "android.widget.Button"))) assertTrue(payload(run(action("findElements").put("selector", selector))).getJSONArray("elements").length() > 0);
        assertEquals(5, payload(run(action("findElements").put("selector", selector("value", "")))).getJSONArray("elements").length());
    }
    @Test public void xpathSupportsNativeAttributesAndNormalizedRoles() {
        JSONObject found = payload(run(action("findElement").put("selector", selector("xpath", "//button[@resource-id='com.example.wallet:id/login']"))));
        assertEquals("login", found.getJSONObject("element").getString("identifier"));
    }
    @Test public void cssSupportsRolesIdsAttributesAndHierarchy() {
        for (String query : Arrays.asList("#login", "button[label='Login']", "other > button#login", "other button[identifier='login']")) {
            assertEquals("login", payload(run(action("findElement").put("selector", selector("cssSelector", query)))).getJSONObject("element").getString("identifier"));
        }
    }
    @Test public void predicateAndUnsupportedCSSReturnCode7() {
        failure(7, action("findElement").put("selector", selector("predicate", "private-secret")));
        failure(7, action("findElement").put("selector", selector("cssSelector", "button:hover")));
        assertFalse(run(action("findElement").put("selector", selector("predicate", "private-secret"))).toString().contains("private-secret"));
    }
    @Test public void scopedQueriesUseAncestryInsteadOfOverlappingFrames() {
        JSONObject scoped = action("findElementsFromElement").put("parent", selector("type", "other")).put("child", selector("type", "button"));
        JSONArray matches = payload(run(scoped)).getJSONArray("elements"); assertEquals(1, matches.length()); assertEquals("login", matches.getJSONObject(0).getString("identifier"));
        scoped.put("type", "findElementFromElement"); assertEquals("login", payload(run(scoped)).getJSONObject("element").getString("identifier"));
    }
    @Test public void missingElementAndWaitTimeoutUseCode8() {
        failure(8, action("findElement").put("selector", selector("label", "missing")));
        failure(8, action("waitFor").put("selector", selector("label", "missing")).put("timeout", 0));
        assertEquals(0, payload(run(action("findElements").put("selector", selector("label", "missing")))).getJSONArray("elements").length());
    }
    @Test public void waitForRequeriesAndDoesNotFailImmediately() {
        Backend changes = new Backend() { @Override public List<UiNode> snapshot() { return ++snapshots > 1 ? nodes : Collections.emptyList(); } };
        JSONObject result = new BridgeExecutor(changes).execute(new JSONObject().put("id", "wait").put("action", button("waitFor").put("timeout", 1)));
        assertTrue(result.getBoolean("success")); assertTrue(changes.snapshots >= 2);
    }
    @Test public void invisibleElementsAreNeverTouched() { failure(11, action("tapElement").put("selector", selector("accessibilityIdentifier", "hidden"))); assertEquals(0, ui.taps); }
    @Test public void gesturesUseDPCentersAndDurations() {
        assertTrue(run(button("tapElement")).getBoolean("success")); assertEquals(84, ui.tapX, .001); assertEquals(124, ui.tapY, .001);
        assertTrue(run(button("doubleTap")).getBoolean("success")); assertEquals(3, ui.taps);
        assertTrue(run(button("longPress").put("duration", .6)).getBoolean("success")); assertEquals(600, ui.duration);
        assertTrue(run(action("tap").put("x", 12).put("y", 24)).getBoolean("success")); assertEquals(12, ui.tapX, .001);
    }
    @Test public void typingClearingAndSubmitHaveConcreteBackendEffects() {
        assertTrue(run(field("typeElement").put("text", "demo")).getBoolean("success")); assertEquals("demo", ui.lastText);
        assertTrue(run(field("clearElement")).getBoolean("success")); assertEquals("", ui.lastText);
        assertTrue(run(field("submit")).getBoolean("success")); assertEquals(1, ui.submits);
        failure(10, button("typeElement").put("text", "private-secret"));
    }
    @Test public void typeRequiresFocusedEditableField() {
        failure(10, action("type").put("text", "demo"));
        ui.nodes = Arrays.asList(new UiNode("f", null, "android.widget.EditText", "field", "", "a", true, true, true, false, true, true, false, true, false, false, 1, 1, 50, 30));
        assertTrue(run(action("type").put("text", "b")).getBoolean("success")); assertEquals("ab", ui.lastText);
    }
    @Test public void elementPropertiesAndRectangleMatchBridgeShape() {
        for (String type : Arrays.asList("elementDisplayed", "elementEnabled")) assertTrue(payload(run(button(type))).getBoolean("value"));
        assertFalse(payload(run(button("elementSelected"))).getBoolean("value"));
        assertEquals("Login", payload(run(button("elementName"))).getString("value"));
        assertEquals(120, payload(run(button("elementRect"))).getJSONObject("value").getDouble("width"), .001);
        for (String attr : Arrays.asList("label", "value", "identifier", "enabled", "exists", "unknown")) assertTrue(payload(run(button("elementAttribute").put("name", attr))).has("value"));
    }
    @Test public void assertionsDoNotLeakActualOrExpectedText() {
        assertTrue(run(button("assertVisible")).getBoolean("success")); assertTrue(run(button("assertText").put("expected", "Login")).getBoolean("success"));
        JSONObject failed = run(button("assertText").put("expected", "private-secret")); assertEquals(6, failed.getInt("errorCode")); assertFalse(failed.toString().contains("private-secret"));
    }
    @Test public void screenshotPayloadIsBinaryBase64AndElementCropIsPassed() {
        byte[] screenshot = Base64.getDecoder().decode(run(action("screenshot")).getString("payloadBase64")); assertEquals((byte)255, screenshot[2]); assertNull(ui.crop);
        assertTrue(run(button("elementScreenshot")).getBoolean("success")); assertEquals("login", ui.crop.identifier);
    }
    @Test public void staticScreenScrollAndClipboardWork() {
        assertTrue(payload(run(action("screenStatic"))).getBoolean("static")); assertEquals(2, ui.screenshots);
        assertTrue(run(action("scroll").put("x", 0).put("y", 100)).getBoolean("success")); assertEquals(1, ui.scrolls);
        assertTrue(run(action("setClipboard").put("text", "demo")).getBoolean("success")); assertEquals("demo", payload(run(action("getClipboard"))).getString("value"));
    }
    @Test public void sequenceStopsOnFailureAndDoesNotPerformLaterActions() {
        failure(8, action("sequence").put("actions", new JSONArray().put(button("tapElement")).put(action("findElement").put("selector", selector("label", "missing"))).put(button("tapElement")))); assertEquals(1, ui.taps);
    }
    @Test public void optionsRemoveNoiseInvisibleAndNonInteractiveAndRespectLimit() {
        JSONObject options = new JSONObject().put("visibleOnly", true).put("hittableOnly", true).put("interactiveOnly", false).put("maxElements", 200);
        JSONObject tree = payload(run(action("accessibilityTreeWithOptions").put("options", options))); assertEquals(3, tree.getInt("count"));
        options.put("interactiveOnly", true).put("maxElements", 1); assertEquals(1, payload(run(action("accessibilityTreeWithOptions").put("options", options))).getInt("count"));
        assertEquals(payload(run(action("accessibilityTree").put("options", options))).toString(), payload(run(action("accessibilityDiff").put("options", options))).toString());
    }
    @Test public void systemAlertsAreOptInAndExposeActiveAlert() {
        ui.nodes = Arrays.asList(new UiNode("system", null, "android.widget.Button", "allow", "Allow", "", true, true, true, false, false, false, false, true, false, true, 1, 1, 50, 30));
        assertEquals(0, payload(run(action("accessibilityTree"))).getInt("count"));
        JSONObject tree = payload(run(action("accessibilityTree").put("options", new JSONObject().put("includeSystemAlerts", true))));
        assertEquals("Allow", tree.getJSONObject("activeAlert").getString("text")); assertEquals("Allow", tree.getJSONObject("activeAlert").getJSONArray("buttons").getString(0));
    }
    @Test public void orderedTreeMatchesFixtureConsumedBySwiftObserve() throws Exception {
        JSONObject tree = BridgeExecutor.tree(ui.nodes, new JSONObject().put("visibleOnly", true).put("hittableOnly", true));
        try (InputStream input = getClass().getResourceAsStream("/runner-tree.json")) {
            assertNotNull(input); JSONObject fixture = new JSONObject(new String(input.readAllBytes(), StandardCharsets.UTF_8));
            assertTrue(tree.similar(fixture));
        }
        assertEquals(tree.toString(), BridgeExecutor.tree(ui.nodes, new JSONObject().put("visibleOnly", true).put("hittableOnly", true)).toString());
    }
    @Test public void densityAndOcclusionKeepCoordinatesAndHittabilityConsistent() {
        assertEquals(24, Geometry.dp(72, 3), .001); assertEquals(72, Geometry.px(24, 3)); assertEquals(25, Geometry.px(10, 2.5));
        assertTrue(Geometry.siblingCovers("root/0", "root/1", true, true, 50, 50, 0, 0, 100, 100));
        assertFalse(Geometry.siblingCovers("root/0", "root/0/1", true, true, 50, 50, 0, 0, 100, 100));
        assertFalse(Geometry.siblingCovers("root/0/1", "root/0", true, true, 50, 50, 0, 0, 100, 100));
        assertFalse(Geometry.siblingCovers("root/0", "root/1", false, true, 50, 50, 0, 0, 100, 100));
        assertFalse(Geometry.siblingCovers("root/0", "root/1", true, true, 150, 50, 0, 0, 100, 100));
    }
    @Test public void sequencesCannotPerformLateTapsAfterCommandBudget() {
        java.util.concurrent.atomic.AtomicLong clock = new java.util.concurrent.atomic.AtomicLong();
        Backend slow = new Backend() { @Override public void tap(double x, double y, int count, long hold) { taps += count; clock.addAndGet(2_000_000_000L); } };
        BridgeExecutor budget = new BridgeExecutor(slow, clock::get, 1000);
        JSONObject result = budget.execute(new JSONObject().put("id", "budget").put("action", action("sequence").put("actions", new JSONArray().put(button("tapElement")).put(button("tapElement")))));
        assertFalse(result.getBoolean("success")); assertEquals(1, slow.taps);
    }
    @Test public void invalidAndUnknownCommandsReturnExplicitSafeFailures() {
        failure(7, action("notSupported")); failure(9, action("findElement")); failure(9, button("longPress").put("duration", -1));
        failure(9, button("waitFor").put("timeout", 30));
        failure(9, action("accessibilityTree").put("options", new JSONObject().put("maxElements", -1)));
    }
}
