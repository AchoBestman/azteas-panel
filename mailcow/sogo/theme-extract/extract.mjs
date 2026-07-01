import { chromium } from "playwright";
import { writeFileSync } from "node:fs";

const url = process.env.SOGO_URL;
const outputPath = process.env.OUTPUT_PATH || "/tmp/custom-theme.css";

if (!url) {
  console.error("SOGO_URL env var is required");
  process.exit(1);
}

const browser = await chromium.launch();
try {
  const page = await browser.newPage();
  await page.goto(url, { waitUntil: "networkidle" });

  // Requires SOGoUIxDebugEnabled = YES in sogo.conf, which serves the raw
  // custom-theme.js instead of a precompiled bundle, so Angular Material
  // computes the theme's <style> tags at runtime.
  const css = await page.evaluate(() => {
    return Array.prototype.slice
      .call(document.styleSheets)
      .map((sheet) => sheet.ownerNode)
      .filter((node) => node && node.hasAttribute && node.hasAttribute("md-theme-style"))
      .map((node) => node.textContent)
      .join("\n");
  });

  if (!css || css.trim().length < 1000) {
    console.error(
      `Extracted CSS looks empty or too short (${css ? css.length : 0} chars). ` +
        "Is SOGoUIxDebugEnabled really set to YES on the server?"
    );
    process.exit(1);
  }

  writeFileSync(outputPath, css);
  console.log(`Wrote ${css.length} bytes to ${outputPath}`);
} finally {
  await browser.close();
}
