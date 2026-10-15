package com.cuycoders.cuyscout;

import org.json.JSONObject;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;

/** Polls the existing gateway. A failed result POST is retried without repeating the action. */
public final class BridgeLoop {
    public interface Transport { String request(String method, String path, String body, int timeoutMs) throws IOException; }
    public static final class HTTPFailure extends IOException {
        public final int status;
        public HTTPFailure(int status) { super("Bridge HTTP status " + status); this.status = status; }
    }
    public static final class HTTP implements Transport {
        private final String base, token;
        public HTTP(String base, String token) throws Exception {
            URI url = new URI(base);
            if (!java.util.Arrays.asList("http", "https").contains(url.getScheme()) || url.getHost() == null || url.getUserInfo() != null || url.getQuery() != null || url.getFragment() != null) throw new IOException("URL de gateway inválida");
            this.base = base.replaceAll("/+$", ""); this.token = token;
        }
        @Override public String request(String method, String path, String body, int timeoutMs) throws IOException {
            HttpURLConnection connection = (HttpURLConnection) new URL(base + path).openConnection();
            connection.setInstanceFollowRedirects(false); connection.setConnectTimeout(timeoutMs); connection.setReadTimeout(timeoutMs);
            connection.setRequestMethod(method);
            if (token != null && !token.isEmpty()) connection.setRequestProperty("Authorization", "Bearer " + token);
            try {
                if (method.equals("POST")) {
                    byte[] data = body == null ? new byte[0] : body.getBytes(StandardCharsets.UTF_8);
                    connection.setDoOutput(true); connection.setFixedLengthStreamingMode(data.length);
                    connection.setRequestProperty("Content-Type", "application/json");
                    try (OutputStream stream = connection.getOutputStream()) { stream.write(data); }
                }
                int status = connection.getResponseCode(); if (status != 200) throw new HTTPFailure(status);
                try (InputStream stream = connection.getInputStream(); ByteArrayOutputStream buffer = new ByteArrayOutputStream()) {
                    byte[] data = new byte[4096]; int count;
                    while ((count = stream.read(data)) != -1) { if (buffer.size() + count > 4 * 1024 * 1024) throw new IOException("Comando demasiado grande"); buffer.write(data, 0, count); }
                    return buffer.toString("UTF-8");
                }
            } finally { connection.disconnect(); }
        }
    }
    private final Transport transport;
    private final BridgeExecutor executor;
    private final String path;
    private boolean registered;
    private String pendingResult;
    public BridgeLoop(Transport transport, BridgeExecutor executor, String sessionID) throws Exception {
        if (!sessionID.matches("[a-zA-Z0-9_-]+")) throw new IOException("Session ID inválido");
        this.transport = transport; this.executor = executor; path = "/session/" + sessionID + "/bridge";
    }
    /** One iteration is exposed for deterministic no-device tests. False means no command. */
    public boolean step() throws Exception {
        if (!registered) { transport.request("POST", path, null, 20000); registered = true; }
        if (pendingResult != null) { transport.request("POST", path + "/result", pendingResult, 20000); pendingResult = null; return true; }
        String body = transport.request("GET", path + "/command", null, 5000);
        if (body == null || body.trim().isEmpty() || body.trim().equals("null")) return false;
        JSONObject command = new JSONObject(body);
        pendingResult = executor.execute(command).toString();
        transport.request("POST", path + "/result", pendingResult, 20000); pendingResult = null; return true;
    }
    public void run(long maxSeconds) throws Exception {
        long deadline = System.nanoTime() + Math.min(Math.max(maxSeconds, 1), 86400) * 1_000_000_000L;
        while (!Thread.currentThread().isInterrupted() && System.nanoTime() < deadline) {
            try { if (!step()) Thread.sleep(200); }
            catch (HTTPFailure status) { if (status.status == 404) return; if (status.status == 401 || status.status == 403 || status.status < 500) throw status; Thread.sleep(200); }
            catch (IOException offline) { Thread.sleep(200); }
        }
    }
}
