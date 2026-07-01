import { chromium } from "playwright";
import { writeFileSync } from "node:fs";

const url = process.env.SOGO_URL;
const outputPath = process.env.OUTPUT_PATH || "/tmp/custom-theme.css";

if (!url) {
  console.error("SOGO_URL env var is required");
  process.exit(1);
}

function readThemeCss() {
  return Array.prototype.slice
    .call(document.styleSheets)
    .map((sheet) => sheet.ownerNode)
    .filter((node) => node && node.hasAttribute && node.hasAttribute("md-theme-style"))
    .map((node) => node.textContent)
    .join("\n");
}

const browser = await chromium.launch();
try {
  const page = await browser.newPage();
  const response = await page.goto(url, { waitUntil: "networkidle" });

  // Requires SOGoUIxDebugEnabled = YES in sogo.conf, which serves the raw
  // custom-theme.js instead of a precompiled bundle, so Angular Material
  // computes the theme's <style> tags at runtime. That computation can lag
  // a bit behind networkidle, so poll for a few seconds instead of reading
  // document.styleSheets exactly once.
  let css = "";
  for (let i = 0; i < 20; i++) {
    css = await page.evaluate(readThemeCss);
    if (css && css.trim().length >= 1000) break;
    await page.waitForTimeout(500);
  }

  if (!css || css.trim().length < 1000) {
    const [styleTagCount, themeStyleTagCount, themeScriptSrc, bodySnippet] = await Promise.all([
      page.evaluate(() => document.querySelectorAll("style").length),
      page.evaluate(() => document.querySelectorAll("style[md-theme-style]").length),
      page.evaluate(() =>
        Array.prototype.slice
          .call(document.querySelectorAll("script[src]"))
          .map((s) => s.getAttribute("src"))
          .filter((src) => src && src.includes("theme"))
      ),
      page.evaluate(() => (document.body ? document.body.innerText.slice(0, 300) : "")),
    ]);

    console.error(
      `Extracted CSS looks empty or too short (${css ? css.length : 0} chars). ` +
        "Is SOGoUIxDebugEnabled really set to YES on the server?"
    );
    console.error(`Diagnostics for ${url}:`);
    console.error(`  HTTP status: ${response ? response.status() : "n/a"}`);
    console.error(`  Page title: ${await page.title()}`);
    console.error(`  <style> tags total: ${styleTagCount}, with [md-theme-style]: ${themeStyleTagCount}`);
    console.error(`  <script src> containing "theme": ${JSON.stringify(themeScriptSrc)}`);
    console.error(`  Body text (first 300 chars): ${JSON.stringify(bodySnippet)}`);
    process.exit(1);
  }

  writeFileSync(outputPath, css);
  console.log(`Wrote ${css.length} bytes to ${outputPath}`);
} finally {
  await browser.close();
}
