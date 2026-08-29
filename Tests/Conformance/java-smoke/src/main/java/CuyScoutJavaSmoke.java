import io.appium.java_client.AppiumClientConfig;
import io.appium.java_client.AppiumDriver;
import io.appium.java_client.remote.options.BaseOptions;
import java.net.URL;

public class CuyScoutJavaSmoke {
    public static void main(String[] args) throws Exception {
        String baseUrl = System.getenv().getOrDefault("CUYSCOUT_URL", "http://127.0.0.1:4723");
        String deviceId = System.getenv("CUYSCOUT_DEVICE_ID");
        if (deviceId == null || deviceId.isEmpty()) {
            throw new IllegalStateException("Define CUYSCOUT_DEVICE_ID");
        }
        BaseOptions<?> options = new BaseOptions<>();
        options.setPlatformName("iOS");
        options.amend("appium:automationName", "XCUITest");
        options.amend("appium:udid", deviceId);
        AppiumClientConfig config = AppiumClientConfig.defaultConfig().baseUrl(new URL(baseUrl));
        AppiumDriver driver = new AppiumDriver(config, options);
        try {
            if (driver.getSessionId() == null) {
                throw new IllegalStateException("CuyScout no devolvió sessionId");
            }
            // El cliente Java normaliza platformName a su enum (IOS); el servidor devuelve "iOS".
            Object platformName = driver.getCapabilities().getCapability("platformName");
            if (!"iOS".equalsIgnoreCase(String.valueOf(platformName))) {
                throw new IllegalStateException("Capabilities W3C inválidas: " + driver.getCapabilities().asMap());
            }
            System.out.println("CuyScout Appium Java smoke: OK (" + driver.getSessionId() + ")");
        } finally {
            driver.quit();
        }
    }
}