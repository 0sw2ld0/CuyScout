package com.cuycoders.cuyscout;

import com.sun.net.httpserver.HttpServer;
import org.json.JSONObject;
import org.junit.Test;
import static org.junit.Assert.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;

public class BridgeLoopTest {
    @Test public void failedResultDeliveryIsRetriedWithoutRepeatingGesture() throws Exception {
        BridgeContractTest.Backend ui = new BridgeContractTest.Backend();
        List<String> paths = new ArrayList<>(); List<String> results = new ArrayList<>();
        BridgeLoop.Transport transport = (method, path, body, timeout) -> {
            paths.add(method + " " + path);
            if (path.endsWith("/command")) { assertEquals(5000, timeout); return "{\"id\":\"c\",\"action\":{\"type\":\"tap\",\"x\":1,\"y\":2}}"; }
            assertEquals(20000, timeout);
            if (path.endsWith("/result")) { results.add(body); if (results.size() == 1) throw new IOException("network lost"); }
            return "{}";
        };
        BridgeLoop loop = new BridgeLoop(transport, new BridgeExecutor(ui), "session-1");
        try { loop.step(); fail(); } catch (IOException expected) { }
        assertEquals(1, ui.taps); assertTrue(loop.step()); assertEquals(1, ui.taps);
        assertEquals(results.get(0), results.get(1));
        assertEquals(Arrays.asList("POST /session/session-1/bridge", "GET /session/session-1/bridge/command", "POST /session/session-1/bridge/result", "POST /session/session-1/bridge/result"), paths);
    }
    @Test public void nullPollDoesNotExecuteAndOnlyRegistersOnce() throws Exception {
        AtomicInteger registration = new AtomicInteger();
        BridgeLoop loop = new BridgeLoop((method, path, body, timeout) -> { if (method.equals("POST")) { registration.incrementAndGet(); assertNull(body); } return "null"; }, new BridgeExecutor(new BridgeContractTest.Backend()), "s");
        assertFalse(loop.step()); assertFalse(loop.step()); assertEquals(1, registration.get());
    }
    @Test public void authAndMissingSessionStopPolling() throws Exception {
        for (int code : new int[]{401, 403, 404}) {
            AtomicInteger calls = new AtomicInteger();
            BridgeLoop loop = new BridgeLoop((m, p, b, t) -> { calls.incrementAndGet(); throw new BridgeLoop.HTTPFailure(code); }, new BridgeExecutor(new BridgeContractTest.Backend()), "s");
            if (code == 404) loop.run(1);
            else try { loop.run(1); fail(); } catch (BridgeLoop.HTTPFailure failure) { assertEquals(code, failure.status); }
            assertEquals(1, calls.get());
        }
    }
    @Test public void HTTPUsesBearerJSONEmptyRegistrationAndRealBridgeRoutes() throws Exception {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        List<String> requests = new ArrayList<>();
        server.createContext("/session/s/bridge", exchange -> {
            assertEquals("Bearer test-token", exchange.getRequestHeaders().getFirst("Authorization"));
            byte[] body = exchange.getRequestBody().readAllBytes(); requests.add(exchange.getRequestMethod() + " " + exchange.getRequestURI());
            if (exchange.getRequestMethod().equals("POST")) {
                assertEquals("application/json", exchange.getRequestHeaders().getFirst("Content-Type"));
                if (exchange.getRequestURI().getPath().endsWith("/result")) assertEquals("c", new JSONObject(new String(body, StandardCharsets.UTF_8)).getString("commandID"));
                else assertEquals(0, body.length);
            }
            String response = exchange.getRequestMethod().equals("GET") ? "{\"id\":\"c\",\"action\":{\"type\":\"screenshot\"}}" : "{}";
            byte[] output = response.getBytes(StandardCharsets.UTF_8); exchange.sendResponseHeaders(200, output.length); exchange.getResponseBody().write(output); exchange.close();
        });
        server.start();
        try {
            BridgeLoop loop = new BridgeLoop(new BridgeLoop.HTTP("http://127.0.0.1:" + server.getAddress().getPort(), "test-token"), new BridgeExecutor(new BridgeContractTest.Backend()), "s");
            assertTrue(loop.step()); assertEquals(3, requests.size());
        } finally { server.stop(0); }
    }
    @Test public void redirectsCannotForwardToken() throws Exception {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0); AtomicInteger target = new AtomicInteger();
        server.createContext("/redirect", exchange -> { exchange.getResponseHeaders().add("Location", "/target"); exchange.sendResponseHeaders(302, -1); exchange.close(); });
        server.createContext("/target", exchange -> { target.incrementAndGet(); exchange.sendResponseHeaders(200, -1); exchange.close(); }); server.start();
        try {
            BridgeLoop.HTTP http = new BridgeLoop.HTTP("http://127.0.0.1:" + server.getAddress().getPort(), "test-token");
            try { http.request("GET", "/redirect", null, 1000); fail(); } catch (BridgeLoop.HTTPFailure status) { assertEquals(302, status.status); }
            assertEquals(0, target.get());
        } finally { server.stop(0); }
    }
    @Test public void invalidURLsAndSessionIDsAreRejected() throws Exception {
        for (String url : Arrays.asList("file:///tmp/a", "http://user:secret@localhost", "http://localhost?token=test")) try { new BridgeLoop.HTTP(url, ""); fail(); } catch (Exception expected) { }
        try { new BridgeLoop((m,p,b,t) -> "null", new BridgeExecutor(new BridgeContractTest.Backend()), "../bad"); fail(); } catch (IOException expected) { }
    }
}
