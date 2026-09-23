---
name: weatherkit-needs-app-services-toggle
description: Automatic signing adds the WeatherKit capability but not the App Services toggle, so every weather request fails JWT auth until it is checked in the portal
metadata:
  type: reference
---

Seen 2026-09-23. `xcodebuild -allowProvisioningUpdates` with the `com.apple.developer.weatherkit` entitlement registered the capability on the App ID and embedded it in the development profile. The launcher still got `WDSJWTAuthenticatorServiceListener.Errors` 2 ("Failed to generate jwt token") on every request, 30+ minutes after the profile was created. In Certificates, Identifiers & Profiles, the App ID had WeatherKit checked under Capabilities but unchecked under App Services.

After checking WeatherKit under App Services and saving, the next request got a JWT and a forecast within a minute. The portal warns that saving invalidates profiles for the App ID. The rebuild right after still embedded the cached profile from before the change, and that build fetched weather fine.

**Why:** the capability, the entitlement and the profile all look correct locally, so the failure seems like a propagation delay when it is really a missing server-side toggle.

**How to apply:** when WeatherKit returns JWT error 2, open the App ID in the portal and check WeatherKit on both the Capabilities and App Services tabs before waiting or rebuilding. Apple's [WeatherKit help page](https://developer.apple.com/help/account/configure-app-services/weatherkit/) names both tabs.
