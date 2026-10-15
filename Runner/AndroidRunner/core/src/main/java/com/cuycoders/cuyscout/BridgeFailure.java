package com.cuycoders.cuyscout;

/** Codes shared with BridgeResult; messages intentionally exclude selectors and UI values. */
public final class BridgeFailure extends Exception {
    public final int code;
    public BridgeFailure(int code, String message) { super(message); this.code = code; }
    public static BridgeFailure missing() { return new BridgeFailure(8, "No se encontró el elemento"); }
    public static BridgeFailure unsupported() { return new BridgeFailure(7, "Acción o selector no soportado; usa accessibilityIdentifier, label o xpath"); }
}
