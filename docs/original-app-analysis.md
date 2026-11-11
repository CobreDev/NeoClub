# AIO Club app (v4.5.29) — analysis

Source: `com.focusonthefamily.Odyssey-Club-4.5.29-Decrypted.ipa` (build 41292, min iOS 12).

## Stack
- **Flutter** app (`Runner` + `App.framework` Dart AOT snapshot), package `adventures_in_odyssey`.
- State: `flutter_bloc` (~45 blocs/cubits). HTTP: `dio`. Generated OpenAPI clients `focus_api` and `focus_api_v2`.
- Audio: `just_audio` + `audio_service` (background audio, lock screen). Video: `video_player`.
- Web content: `flutter_inappwebview` / `webview_flutter` (sign-in, articles, membership pages).
- Storage: `sqflite`, `shared_preferences`, `flutter_secure_storage`. Downloads tracked in `downloads.json`.
- Firebase: Messaging (push), Remote Config (incl. API rate-limiter settings), Crashlytics, In-App Messaging, A/B testing.

## Backend — Salesforce Experience Cloud
| Purpose | URL |
|---|---|
| REST v1 | `https://fotf.my.site.com/aio/services/apexrest/v1` |
| REST v2 | `https://fotf.my.site.com/aio/services/apexrest/v2` |
| OAuth authorize | `https://fotf.my.site.com/aio/services/oauth2/authorize` |
| OAuth token | `https://fotf.my.site.com/aio/services/oauth2/token` |
| OAuth revoke | `https://fotf.my.site.com/aio/services/oauth2/revoke` |
| Redirect URI | `https://app.adventuresinodyssey.com/callback` |
| Web app | `https://app.adventuresinodyssey.com` |

Auth: OAuth 2 authorization-code + **PKCE** (`response_type=code&client_id=…&redirect_uri=…&code_challenge=…&scope=api web refresh_token`), then `Authorization: Bearer <token>`.
The client ID is **not** a literal in the iOS binary. The public Flutter-web build (`app.adventuresinodyssey.com/main.dart.js`) has it:
`3MVG9l2zHsylwlpTFc1ZB3ryOQlpLYIqNo0UV4d0lBRjkbb6TXbw9UNhdcJfom2nnbB.AbNpkRbGoTfruF0gB`. Verified on 2026-11-11: `/authorize` with this ID plus the callback redirect returns 302 to the login page, while a bogus ID returns 400.
Because the redirect is an https URL on a domain we don't control, sign-in must run in a `WKWebView` that intercepts navigation to `/callback?code=…` (that is what the Flutter app does), not `ASWebAuthenticationSession`.

Per-request headers seen: `X-Viewer-Id` (selected child/viewer profile), `X-Experience-Name`.

## Endpoints (from generated client method names)
- **Content**: `GET /content/{contentId}`, `GET /content/search`, `GET /content/random`, `GET /content/help`, `PUT /content` (progress)
- **Groupings** (albums, series, collections, playlists): `POST /contentgrouping/search`, `POST /contentgrouping/adventures/search`, `GET|DELETE /contentgrouping/{id}`, `POST|PUT /contentgrouping`
- **Search**: `POST /search`
- **Characters / cast**: `POST /character/search`, `GET /character/{id}`, `POST /author/search`, `GET /author/{id}`
- **Badges**: `POST /badge/search`, `GET /badge/{id}`, `POST /badgerequirement/{id}`
- **Topics / themes**: `POST /topic/search`, `GET /topic/{id}`, `POST /topic/exclusions`
- **Bookmarks**: `POST|DELETE /bookmark`
- **Comments**: `POST /comment/search`, `POST /comment`, `DELETE /comment/{id}`, `PUT /comment/report`
- **Viewer (child profiles)**: `GET|POST|PUT /viewer`, `DELETE /viewer/{id}`, `GET /viewer/home`, `GET /viewer/verifyPIN`, `GET /viewer/PINReminder`, `POST /viewer/verifyUsername`, `POST /viewer/notification`
- **User**: `GET|POST|PATCH /user`, `PUT /user/findOrCreateContact`
- **Navigation**: `GET /navigation`; **Store**: `GET /store`
- **Membership** (purchase/gift — keep on web): `GET /membership`, `GET /membership/type`, `PUT /membership/order`, `POST /membership/submitpayment`, `/saveshipping`, `/cancel`, `/claimgiftcode`, `GET /membership/verifyGiftCode`, `POST /chargent/token`
- **Misc**: `POST /case` (feedback), `POST /error/log`, `GET /public/memberships`, `GET /public/experienceUsers`

Key content fields: `content_type`, `subtype`, `stream_url`, `download_url`, `duration`, `thumbnail_small`, `thumbnail_large`, `image_url`, `episode_number`, `air_date`, `progress_events`.

## Features / screens in the Flutter app
Home (carousel, "where you left off", Odyssey Times), content detail (audio, video, article, download, product), content groups (albums, series, collections, adventures), search, characters, cast, themes, badges & adventures, playlists (create/edit), bookmarks, downloads (offline), radio station list, comments, notifications, viewer profiles with PIN + content exclusions, settings, help/FAQ/feedback, membership flows (purchase, gift purchase/claim, cancel), audio player (mini + expanded + queue), video player.
