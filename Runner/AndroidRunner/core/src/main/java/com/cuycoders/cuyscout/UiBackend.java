package com.cuycoders.cuyscout;

import java.util.List;

/** Platform boundary: no Android types leak into the protocol/selector tests. */
public interface UiBackend {
    List<UiNode> snapshot() throws Exception;
    void tap(double x, double y, int count, long durationMs) throws Exception;
    void setText(UiNode node, String text) throws Exception;
    void submit(UiNode node) throws Exception;
    void scroll(double x, double y) throws Exception;
    byte[] screenshot(UiNode crop) throws Exception;
    void clipboard(String text) throws Exception;
    String clipboard() throws Exception;
}
