package com.cuycoders.cuyscout;

public final class Geometry {
    private Geometry() {}
    public static double dp(double pixels, double density) { if (!(density > 0)) throw new IllegalArgumentException("Invalid density"); return pixels / density; }
    public static int px(double dp, double density) { if (!(density > 0) || !Double.isFinite(dp)) throw new IllegalArgumentException("Invalid coordinate"); return (int)Math.round(dp * density); }
    public static boolean siblingCovers(String key, String otherKey, boolean visible, boolean actionable, double x, double y, double left, double top, double right, double bottom) {
        // Bounds first: they rule out almost every pair without building strings.
        return visible && actionable && x >= left && x < right && y >= top && y < bottom
            && !key.equals(otherKey) && !otherKey.startsWith(key + "/") && !key.startsWith(otherKey + "/");
    }
}
