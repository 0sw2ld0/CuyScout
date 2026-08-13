import { remote } from "webdriverio";

const deviceId = process.env.CUYSCOUT_DEVICE_ID;
if (!deviceId) throw new Error("Define CUYSCOUT_DEVICE_ID");

const browser = await remote({
  hostname: new URL(process.env.CUYSCOUT_URL ?? "http://127.0.0.1:4723").hostname,
  port: Number(new URL(process.env.CUYSCOUT_URL ?? "http://127.0.0.1:4723").port || 4723),
  path: "/",
  capabilities: {
    platformName: "iOS",
    "appium:automationName": "XCUITest",
    "appium:udid": deviceId,
  },
});

try {
  if (!browser.sessionId || browser.capabilities.platformName !== "iOS") throw new Error("Invalid W3C capabilities");
  console.log(`CuyScout WebdriverIO smoke: OK (${browser.sessionId})`);
} finally {
  await browser.deleteSession();
}
