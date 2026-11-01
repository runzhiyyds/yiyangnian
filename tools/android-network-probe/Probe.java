import java.net.HttpURLConnection;
import java.net.URL;

/** Read-only Android transport probe. Never sends account credentials or app data. */
public final class Probe {
  private static final String[][] TARGETS = {
      {"direct", "https://jhntjagskjklbrsgturh.supabase.co/auth/v1/health"},
      {"gateway", "https://yiyangnian-api.pet-food-advisor.asia/health"},
  };

  public static void main(String[] args) throws Exception {
    int rounds = args.length == 0 ? 8 : Integer.parseInt(args[0]);
    for (int round = 0; round < rounds; round++) {
      for (int offset = 0; offset < TARGETS.length; offset++) {
        String[] target = TARGETS[(round + offset) % TARGETS.length];
        long start = System.nanoTime();
        HttpURLConnection connection = null;
        try {
          connection = (HttpURLConnection) new URL(target[1]).openConnection();
          connection.setRequestMethod("GET");
          connection.setConnectTimeout(6000);
          connection.setReadTimeout(12000);
          connection.setUseCaches(false);
          int status = connection.getResponseCode();
          // Read the complete response, including an upstream non-2xx health status.
          java.io.InputStream body = status < 400
              ? connection.getInputStream() : connection.getErrorStream();
          if (body != null) {
            byte[] buffer = new byte[4096];
            while (body.read(buffer) != -1) {}
            body.close();
          }
          System.out.println(round + " " + target[0] + " status=" + status
              + " ms=" + elapsedMs(start));
        } catch (Exception error) {
          System.out.println(round + " " + target[0] + " error="
              + error.getClass().getSimpleName() + " ms=" + elapsedMs(start));
        } finally {
          if (connection != null) connection.disconnect();
        }
      }
    }
  }

  private static long elapsedMs(long start) {
    return (System.nanoTime() - start) / 1000000;
  }
}
