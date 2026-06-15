# EasyOffice Messenger (Flutter / Android)

A modern messaging client for **easyoffice.gm**, built against the existing
`apps.mobile_api` DRF endpoints and the `apps.messaging` `ChatConsumer`
WebSocket. It supports JWT login, a conversation inbox, live 1‑on‑1 and group
chat, replies, emoji reactions, polls, typing indicators, presence, and user
search.

> **Why isn't there a prebuilt APK in this repo?**
> The environment this project was generated in cannot reach Google's servers
> (`dl.google.com`, `pub.dev`, `storage.googleapis.com`), so it cannot run a
> Flutter build. Instead, the included GitHub Actions workflow builds the APK
> for you on GitHub's runners. See **"Get the APK"** below — it's one push.

---

## Get the APK (no local setup needed)

1. Create a new GitHub repository.
2. Push this project to it:
   ```bash
   cd easyoffice_messenger
   git init && git add . && git commit -m "EasyOffice Messenger"
   git branch -M main
   git remote add origin https://github.com/<you>/<repo>.git
   git push -u origin main
   ```
3. Open the repo's **Actions** tab. The **Build Android APK** workflow runs
   automatically. When it finishes (~5 min), open the run and download the
   **easyoffice-messenger-apk** artifact. Unzip it to get `app-release.apk`.
4. Copy the APK to your phone, tap it, and allow "Install unknown apps" when
   prompted. (Tagging a commit `v1.0.0` also attaches the APK to a Release.)

## Or build it locally

Requires the Flutter SDK (https://docs.flutter.dev/get-started/install) and an
Android device/emulator.

```bash
cd easyoffice_messenger
flutter pub get
flutter run                 # to a connected phone/emulator
# or
flutter build apk --release # outputs build/app/outputs/flutter-apk/app-release.apk
```

---

## Point it at your server

Edit **`lib/config.dart`**:

- `host` — your deployment origin (default `https://easyoffice.gm`).
- `apiPrefix` — **the path where `apps.mobile_api.urls` is mounted** in your
  root `urls.py`. The default guess is `/api/mobile`. Check your project's main
  `urls.py` for the line that does `include('apps.mobile_api.urls')` and set
  this to match its prefix.
- `wsChatPath` — the WebSocket route prefix (default `/ws/chat`). Must match
  your Channels `routing.py`.

---

## Server-side checklist (two things to confirm)

The REST side is ready: every endpoint the app calls already exists in
`apps/mobile_api/urls.py`. Two items depend on files that weren't available and
should be verified:

### 1. WebSocket JWT authentication

`ChatConsumer.connect()` does `self.user = self.scope['user']` and closes the
socket unless `is_authenticated`. With a browser this works via Django's
`AuthMiddlewareStack` (session cookie). **Mobile clients have no session
cookie** — this app sends the JWT as a `?token=...` query parameter on the
WebSocket URL, so you need a small middleware that reads it. Add to your ASGI
config (e.g. `asgi.py`):

```python
# apps/messaging/ws_auth.py
from urllib.parse import parse_qs
from channels.db import database_sync_to_async
from django.contrib.auth.models import AnonymousUser

@database_sync_to_async
def _user_from_token(token):
    from rest_framework_simplejwt.tokens import AccessToken
    from apps.core.models import User
    try:
        data = AccessToken(token)
        return User.objects.get(id=data["user_id"])
    except Exception:
        return AnonymousUser()

class JWTAuthMiddleware:
    def __init__(self, app):
        self.app = app
    async def __call__(self, scope, receive, send):
        qs = parse_qs(scope.get("query_string", b"").decode())
        token = (qs.get("token") or [None])[0]
        if token:
            scope["user"] = await _user_from_token(token)
        return await self.app(scope, receive, send)
```

Then wrap your chat routes with both stacks so cookie auth still works on web:

```python
# asgi.py
from channels.auth import AuthMiddlewareStack
from channels.routing import ProtocolTypeRouter, URLRouter
from apps.messaging.ws_auth import JWTAuthMiddleware
import apps.messaging.routing as chat_routing

application = ProtocolTypeRouter({
    "websocket": JWTAuthMiddleware(
        AuthMiddlewareStack(URLRouter(chat_routing.websocket_urlpatterns))
    ),
})
```

And confirm `routing.py` has a pattern matching `ws/chat/<room_id>/`, e.g.:

```python
# apps/messaging/routing.py
from django.urls import re_path
from .consumers import ChatConsumer
websocket_urlpatterns = [
    re_path(r"ws/chat/(?P<room_id>[0-9a-f-]+)/$", ChatConsumer.as_asgi()),
]
```

### 2. CORS

If the API host differs from where the app runs, ensure `django-cors-headers`
allows it. For a packaged mobile app calling `https://easyoffice.gm` directly,
this usually isn't needed, but verify `ALLOWED_HOSTS` includes your domain.

---

## What's wired to what

| App feature            | Backend it uses                                   |
|------------------------|---------------------------------------------------|
| Login / session        | `auth/login/`, `auth/refresh/`, `auth/me/`        |
| Inbox                  | `rooms/`                                           |
| Open a DM              | `rooms/direct/` (POST `user_id`)                  |
| Message history        | `rooms/<id>/messages/`                            |
| Live send / receive    | `ChatConsumer` over `ws/chat/<id>/`               |
| Typing indicator       | `ChatConsumer` `typing` ⇄ `chat_typing`           |
| Reactions              | `messages/<id>/react/`                            |
| Delete message         | `DELETE messages/<id>/`                           |
| Polls                  | `rooms/<id>/polls/`, `polls/<id>/vote/`           |
| Presence               | `presence/heartbeat/`, `presence/<id>/`           |
| User search            | `users/search/`                                   |

If any REST view expects different request keys than the client sends
(e.g. `rooms/direct/` wanting `user` instead of `user_id`), adjust the matching
method in `lib/services/api_service.dart` — each is small and clearly named.

## Design

Deep institutional teal + warm sand, Sora display / Inter body type. Own
messages use a brighter signal teal with an asymmetric squared tail corner;
online direct chats show a softly breathing coral presence ring.
