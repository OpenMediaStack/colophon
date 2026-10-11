import "@fontsource-variable/inter";
import "@fontsource-variable/jetbrains-mono";
import "@fontsource-variable/newsreader/wght-italic.css";
import "./main.css";

const REPOSITORY = "OpenMediaStack/colophon";

/** The file of each platform among a release's assets. */
const PLATFORMS = {
  mac: { name: "macOS", file: (name) => name.endsWith(".dmg") },
  windows: { name: "Windows", file: (name) => name.endsWith("-setup.exe") },
  linux: { name: "Linux", file: (name) => name.endsWith(".AppImage") },
};

/** The visitor's desktop platform, or none on a phone or a tablet. */
function visitorPlatform() {
  const agent = navigator.userAgent;
  if (/Android|iPhone|iPad|iPod/.test(agent) || navigator.userAgentData?.mobile) {
    return null;
  }
  const platform = (navigator.userAgentData?.platform || navigator.platform || agent).toLowerCase();
  if (platform.includes("mac")) return "mac";
  if (platform.includes("win")) return "windows";
  if (platform.includes("linux")) return "linux";
  return null;
}

/** Points the download links at the files of the latest release, and the hero at the visitor's. */
async function linkLatestRelease() {
  const response = await fetch(`https://api.github.com/repos/${REPOSITORY}/releases/latest`);
  if (!response.ok) return;
  const release = await response.json();
  const version = release.tag_name.replace(/^v/, "");
  for (const element of document.querySelectorAll("[data-version]")) {
    element.textContent = `v${version}`;
  }
  const files = {};
  for (const [key, platform] of Object.entries(PLATFORMS)) {
    const asset = release.assets.find((asset) => platform.file(asset.name));
    if (asset) files[key] = asset.browser_download_url;
  }
  for (const link of document.querySelectorAll("[data-download]")) {
    const file = files[link.dataset.download];
    if (file) link.href = file;
  }
  const platform = visitorPlatform();
  const hero = document.querySelector("[data-download-hero]");
  if (hero && platform && files[platform]) {
    hero.href = files[platform];
    hero.querySelector("[data-download-label]").textContent = `Download for ${PLATFORMS[platform].name}`;
  }
}

/** The player card's waveform: a song's rise and fall, with some grain, played to 38%. */
function drawWaveform() {
  const waveform = document.querySelector("[data-waveform]");
  if (!waveform) return;
  let grain = 7;
  for (let index = 0; index < 64; index++) {
    grain = (grain * 1103515245 + 12345) % 2147483648;
    const place = index / 64;
    const swell = 0.55 + 0.3 * Math.sin(place * 9) * Math.cos(place * 2.2);
    const level = Math.min(1, Math.max(0.14, swell + 0.25 * ((grain >> 16) / 32767)));
    const bar = document.createElement("span");
    bar.className = `min-w-px flex-1 rounded-[1px] ${place < 0.38 ? "bg-accent" : "bg-line-strong"}`;
    bar.style.height = `${Math.round(level * 100)}%`;
    waveform.append(bar);
  }
}

/** Repeats the ticker's words once, so that it loops without a gap, then sets it moving. */
function startTicker() {
  const ticker = document.querySelector("[data-ticker]");
  if (!ticker) return;
  ticker.append(...[...ticker.children].map((word) => word.cloneNode(true)));
  ticker.classList.add("animate-ticker");
}

drawWaveform();
startTicker();
linkLatestRelease().catch(() => {});
