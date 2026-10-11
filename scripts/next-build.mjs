// Works out the next build number: 1, 2, 3, … within the current version.
//
// Apple's only rule is that the build number climbs for a given marketing
// version, so rather than keeping a counter in the repo (which drifts the
// moment anyone uploads from another machine), ask App Store Connect what it
// has already seen and add one.
//
//   node Scripts/next-build.mjs <marketing version>

import { asc, APP_ID } from "./asc.mjs";

const VERSION = process.argv[2];
if (!VERSION) {
  console.error("usage: next-build.mjs <marketing version>");
  process.exit(1);
}

// Guessing here would mean a rejected upload twenty minutes from now, so a
// failure to ask is a failure to ship.
const { data } = await asc(
  `/v1/builds?filter[app]=${APP_ID}` +
    `&filter[preReleaseVersion.version]=${encodeURIComponent(VERSION)}` +
    `&limit=200`
).catch((error) => {
  console.error(error.message);
  process.exit(1);
});
const highest = data
  .map((build) => Number(build.attributes.version))
  .filter((n) => Number.isFinite(n))
  .reduce((a, b) => Math.max(a, b), 0);

console.log(String(highest + 1));
