package com.cuycoders.cuyscout;

import org.json.JSONObject;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NodeList;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.xpath.XPathConstants;
import javax.xml.xpath.XPathFactory;
import java.util.*;
import java.util.regex.*;

public final class Selectors {
    private Selectors() {}
    public static List<UiNode> find(List<UiNode> nodes, JSONObject selector, UiNode parent) throws Exception {
        if (selector == null || !selector.has("strategy") || !selector.has("value")) throw new BridgeFailure(9, "Falta un selector válido");
        String strategy = selector.getString("strategy"), value = selector.getString("value");
        if (value.length() > 4096) throw BridgeFailure.unsupported();
        if (!Arrays.asList("accessibilityIdentifier", "id", "label", "value", "type", "xpath", "cssSelector").contains(strategy)) throw BridgeFailure.unsupported();
        Map<String, UiNode> byKey = new HashMap<>(); for (UiNode node : nodes) byKey.put(node.key, node);
        List<UiNode> candidates = new ArrayList<>();
        for (UiNode node : nodes) if (parent == null || descendant(node, parent, byKey)) candidates.add(node);
        if (strategy.equals("xpath") || strategy.equals("cssSelector")) return xpath(nodes, candidates, strategy.equals("xpath") ? value : cssXPath(value), parent);
        List<UiNode> result = new ArrayList<>();
        for (UiNode node : candidates) {
            boolean match;
            switch (strategy) {
                case "accessibilityIdentifier": case "id": match = node.identifier.equals(UiNode.identifier(value)); break;
                case "label": match = sameText(node.label, value); break;
                case "value": match = sameText(node.value, value); break;
                case "type": match = node.type.equalsIgnoreCase(value) || node.className.equals(value); break;
                default: throw BridgeFailure.unsupported();
            }
            if (match) result.add(node);
        }
        return result;
    }
    /** Texts compare as a person reads them. React Native often pads a text or joins it with a no-break space
     *  («**** 1234», «15.00 »), and observe shows texts trimmed: an exact match made the agent's checks fail
     *  with «not found» on text that was on screen. */
    public static String normalize(String text) {
        return text.replace('\u00A0', ' ').replace('\u202F', ' ').replaceAll("\\s+", " ").trim();
    }
    public static boolean sameText(String actual, String expected) { return actual.equals(expected) || normalize(actual).equals(normalize(expected)); }
    private static boolean descendant(UiNode node, UiNode parent, Map<String, UiNode> byKey) {
        String key = node.parent;
        while (key != null) { if (key.equals(parent.key)) return true; UiNode next = byKey.get(key); key = next == null ? null : next.parent; }
        return false;
    }
    private static List<UiNode> xpath(List<UiNode> all, List<UiNode> candidates, String expression, UiNode parent) throws Exception {
        Document doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().newDocument();
        Element root = doc.createElement("hierarchy"); doc.appendChild(root);
        Map<String, Element> elements = new HashMap<>(); Map<String, UiNode> byKey = new HashMap<>();
        for (UiNode node : all) {
            Element e = doc.createElement(node.type);
            e.setAttribute("key", node.key); e.setAttribute("identifier", node.identifier); e.setAttribute("label", node.label);
            e.setAttribute("value", node.value); e.setAttribute("class", node.className); e.setAttribute("resource-id", node.resourceId);
            e.setAttribute("text", node.editable ? node.value : node.label); e.setAttribute("content-desc", node.label);
            e.setAttribute("enabled", Boolean.toString(node.enabled));
            elements.getOrDefault(node.parent, root).appendChild(e); elements.put(node.key, e); byKey.put(node.key, node);
        }
        Object context = parent == null ? doc : elements.get(parent.key);
        if (parent != null && expression.startsWith("//")) expression = "." + expression;
        try {
            NodeList matched = (NodeList) XPathFactory.newInstance().newXPath().evaluate(expression, context, XPathConstants.NODESET);
            Set<String> keys = new HashSet<>();
            for (int i = 0; i < matched.getLength(); i++) if (matched.item(i) instanceof Element) keys.add(((Element) matched.item(i)).getAttribute("key"));
            List<UiNode> result = new ArrayList<>();
            for (UiNode node : candidates) if (keys.contains(node.key)) result.add(node);
            return result;
        } catch (javax.xml.xpath.XPathExpressionException invalid) { throw BridgeFailure.unsupported(); }
    }
    /** Deliberately bounded native CSS: role, #resource-id, attributes, descendants and >. */
    private static String cssXPath(String css) throws BridgeFailure {
        List<String> tokens = new ArrayList<>(); StringBuilder token = new StringBuilder(); char quote = 0; int brackets = 0;
        for (char c : css.toCharArray()) {
            if (quote != 0) { token.append(c); if (c == quote) quote = 0; continue; }
            if (c == '\'' || c == '"') { quote = c; token.append(c); continue; }
            if (c == '[') brackets++; if (c == ']') brackets--;
            if (brackets == 0 && (Character.isWhitespace(c) || c == '>')) {
                if (token.length() > 0) { tokens.add(token.toString()); token.setLength(0); }
                if (c == '>') tokens.add(">");
            } else token.append(c);
        }
        if (token.length() > 0) tokens.add(token.toString());
        if (quote != 0 || brackets != 0 || tokens.isEmpty()) throw BridgeFailure.unsupported();
        StringBuilder xpath = new StringBuilder(); boolean direct = false;
        for (String item : tokens) {
            if (item.equals(">")) { if (xpath.length() == 0 || direct) throw BridgeFailure.unsupported(); direct = true; continue; }
            Matcher m = Pattern.compile("^(\\*|[a-zA-Z][a-zA-Z0-9]*)?(?:#([a-zA-Z0-9_.:-]+))?((?:\\[[^\\]]+\\])*)$").matcher(item);
            if (!m.matches() || item.isEmpty()) throw BridgeFailure.unsupported();
            xpath.append(direct ? "/" : "//").append(m.group(1) == null ? "*" : m.group(1).toLowerCase(Locale.ROOT)); direct = false;
            if (m.group(2) != null) xpath.append("[@identifier=").append(literal(UiNode.identifier(m.group(2)))).append("]");
            Matcher attr = Pattern.compile("\\[([a-zA-Z-]+)\\s*=\\s*(['\"])(.*?)\\2\\]").matcher(m.group(3)); int end = 0;
            while (attr.find()) {
                if (attr.start() != end) throw BridgeFailure.unsupported(); end = attr.end();
                String name = attr.group(1); if (name.equals("id")) name = "identifier";
                if (!Arrays.asList("identifier", "label", "value", "class", "resource-id", "text", "content-desc", "enabled").contains(name)) throw BridgeFailure.unsupported();
                xpath.append("[@").append(name).append("=").append(literal(attr.group(3))).append("]");
            }
            if (end != m.group(3).length()) throw BridgeFailure.unsupported();
        }
        if (direct) throw BridgeFailure.unsupported(); return xpath.toString();
    }
    private static String literal(String text) throws BridgeFailure {
        if (!text.contains("'")) return "'" + text + "'";
        if (!text.contains("\"")) return "\"" + text + "\"";
        throw BridgeFailure.unsupported();
    }
}
