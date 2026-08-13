import os

from appium import webdriver
from appium.options.ios import XCUITestOptions


server_url = os.environ.get("CUYSCOUT_URL", "http://127.0.0.1:4723")
device_id = os.environ["CUYSCOUT_DEVICE_ID"]
options = XCUITestOptions().load_capabilities({
    "platformName": "iOS",
    "appium:automationName": "XCUITest",
    "appium:udid": device_id,
})
driver = webdriver.Remote(server_url, options=options)
try:
    assert driver.session_id
    assert driver.capabilities.get("platformName") == "iOS"
    print(f"CuyScout Appium Python smoke: OK ({driver.session_id})")
finally:
    driver.quit()
