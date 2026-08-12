---
name: tapestry-client-features
description: Add UI functionality to asteasolutions/tapestry-project's client — new canvas item types, toolbar features, auth providers, and build-time config, following the existing core/core-client/client/viewer layering
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["tapestry-project client", "client/src", "stage controller", "item factory", "canvas item type"]
  - keywords: ["ItemController", "EditorItemController", "socket-manager", "tapestry-updated"]
  - keywords: ["auth provider", "VITE_AUTH_PROVIDER", "config.ts", "item toolbar"]
last_verified: 2026-08-12
---

Conventions for adding UI functionality to `tapestry-project`'s `client` — how the
`core`/`core-client`/`client`/`viewer` layers divide responsibility, the
controller/manager pattern for canvas interactions, how live updates and auth work,
and the idiomatic shape of a new component.

## When to use this skill

- Adding a new canvas item type, or a new draggable/pasteable import source
- Adding a toolbar button, menu item, or dialog on an item
- Adding a new auth provider
- Adding a new `VITE_*` build-time config value
- Any question about whether new client code belongs in `client`, `core-client`, or `core`

## The four client-side workspaces

| Workspace | Role |
|---|---|
| `core` (`tapestry-core`) | Data-format Zod schemas, generic geometry/algebra/web-source utils. No React, no server awareness. |
| `core-client` (`tapestry-core-client`) | Generic, app-agnostic canvas engine: base `ItemController`, view-model store, generic item components, reusable UI primitives (`IconButton`, `SimpleModal`, `FilePicker`, hooks like `useKeyboardShortcuts`, `useItemMenu`). Both `client` and `viewer` build on this. |
| `client` | The real deployed app — authoring (WYSIWYG editor) + authenticated, live-collaborative viewing. REST + Socket.io talk to `server`. |
| `viewer` | A separate, small, **standalone** app — no `tapestry-shared`, no `axios`/`socket.io-client`, no auth. Loads a tapestry from a `source=` URL or local IndexedDB blob, renders it read-only using `core-client`'s default components. This is what the exported `.zip` (via `client`'s export button → `TapestryExporter`) is meant to be opened with — an offline/standalone single-tapestry viewer, distinct from the full app. |

Rule of thumb: if the code needs auth, live sockets, or multi-tapestry app chrome, it
belongs in `client`. If it's generic canvas/rendering/interaction logic reusable by a
read-only standalone viewer too, it belongs in `core-client`. If it's a pure data
shape/schema with no UI, it belongs in `core`.

Imports cross workspace boundaries by package name into `src` directly (e.g.
`tapestry-core-client/src/stage/controller/item-controller`, `tapestry-shared/src/data-transfer/resources/dtos/item`),
not through a built package entry point.

## `client/src/` top level

`assets/`, `auth/`, `components/`, `config.ts`, `errors/`, `hooks/`, `layouts/`, `lib/`,
`main.tsx`, `model/`, `pages/`, `providers/`, `sentry-init.ts`, `services/`, `stage/`,
`utils/`.

## Stage/controller pattern

Two layers of controllers:

- `core-client/src/stage/controller/` — generic: `item-controller.ts` (abstract
  `ItemController` base), `global-events-controller.ts`, `item-thumbnail-controller.ts`,
  `viewport-controller.ts`.
- `client/src/stage/controller/` — editor-specific subclasses/managers:
  `editor-item-controller.ts`, `editor-rel-controller.ts`, `editor-global-events-controller.ts`,
  `item-resize-manager.ts`, `presentation-order-controller.ts`.

`EditorItemController extends ItemController`. It:
- Owns collaborator objects (e.g. a `DomDragHandler` for drag, another for resize)
  created in `init()` and torn down in `dispose()`.
- Registers listeners with a **decorator-based typed event registry** —
  `createEventRegistry<EventTypesMap, InteractionMode | 'desktop' | 'mobile'>()`, then
  `@eventListener('resizeHandler', 'dragstart', ['edit'])` on protected methods.
  Listeners attach/detach per `InteractionMode` via a store subscription
  (`editorStore.subscribe('interactionMode', onInteractionModeChange)`) — copy this
  pattern rather than manually wiring/unwiring DOM listeners in lifecycle methods.
- Delegates non-trivial math to a separate **manager** collaborator rather than doing
  it inline: `ItemResizeManager` (constructed with `(editorStore, stage)`) owns
  per-`ItemType` bounds/aspect-ratio/min-max-size logic (`maxSizeByType: Partial<Record<ItemType, Size>>`)
  and exposes `startResize`/`resize`/`endResize`/`forceLockAspectRatio` for the
  controller to call from its drag-event handlers. This manager pattern (instantiate
  from the controller, pass store + stage, call narrow methods) is the template for
  any new non-trivial per-item interaction behavior.
- Mutates state through composable **store commands** — plain functions from
  `client/src/pages/tapestry/view-model/store-commands/{items,tapestry}.ts` (e.g.
  `setInteractiveElement`, `updateSelectionItems`, `selectItem`), passed (often several
  at once, some conditionally) to `editorStore.dispatch(...)`. Don't mutate the store
  directly from a controller — go through a command.

## Adding a new import source (drag/drop or paste)

`client/src/stage/item-factories.ts` defines `ITEM_FACTORIES: ItemFactory[]`, an ordered
array of `(source, mediaType, tapestryId) => Promise<{items, iaImports} | null>`
functions tried in sequence (media-type factories for image/book/pdf/video/audio, then
`linkFileFactory`, `textItemFactory`, `htmlFileItemFactory`, `iaCollectionFactory`, and
`webpageItemFactory` as the catch-all). To support a new source: write a new factory and
insert it **before** the webpage catch-all.

## Adding a brand-new canvas item type

This touches every layer. See `tapestry-content-types` for the complete, verified
checklist (generalized from a real reference implementation, including the
easy-to-miss export-version bump and the client-side item-factory/sizing steps this
summary doesn't cover). Short version, client-side only:

1. **`core/src/data-format/schemas/item.ts`** — add a `z.literal('yourType')`-tagged
   variant to the `Item`/`MediaItem` discriminated union (existing: `text`,
   `actionButton`, `audio`, `book`, `image`, `pdf`, `video`, `webpage`). `ItemType`
   is derived from this automatically — you don't declare it separately.
2. **`core-client/src/components/tapestry/index.tsx`** — `TapestryComponentsConfig` is
   `Record<ItemComponentName<Exclude<ItemType,'webpage'>>, TapestryElementComponent>`
   (name computed as `${Capitalize<T>}Item`). TypeScript will now force every consumer
   of this config to supply a component for the new type — that's your compile-time
   checklist.
3. **`client/src/components/tapestry-elements/items/<yourtype>/index.tsx`** — new
   component folder, mirroring `image/`, `video/`, `audio/`, `pdf/`, `book/`, `text/`,
   `webpage/`, `action-button/`, `wayback-page/` (each just `index.tsx`, most with a
   co-located `styles.module.css`).
4. **Register the component** in `client/src/pages/tapestry/tapestry-loader.tsx` (the
   real app's components map for `TapestryConfigProvider`) — and in `core-client/src/components/tapestry/index.tsx`'s
   own `defaults(...)` fallback block if a sensible generic default makes sense (needed
   for `viewer` to render it too).
5. Rendering dispatch happens in `core-client/src/components/tapestry/tapestry-canvas/index.tsx`'s
   `renderItem()` (`components[itemComponentName(item.dto.type)]`; `webpage` is
   special-cased on `webpageType`).
6. If it needs resize/drag behavior beyond the defaults, extend `maxSizeByType`/
   `shouldLockAspectRatio` in `client/src/stage/controller/item-resize-manager.ts`.
7. If it should be creatable by dropping a file/pasting a URL, add an `ItemFactory`
   (previous section).

## Live updates — `socket-manager.ts`

`client/src/pages/tapestry/view-model/socket-manager.ts`'s `SocketManager` wraps one
`socket.io-client` connection:

```ts
private socket: Socket<ServerToClientEvents, ClientToServerEvents> = io(
  new URL(config.apiUrl).origin,
  { path: SOCKET_PATH, autoConnect: false, auth: (cb) => cb({ token: auth.token }) },
)
```

`autoConnect` is off — the caller decides when to `connect()`/`disconnect()`/`dispose()`
(e.g. on entering/leaving a tapestry page). On `'connect'`, it emits `'subscribe'` for
`'tapestry-updated'` with an ack callback that delivers the current snapshot once, then
a persistent `'tapestry-updated'` listener handles subsequent pushes — **subsequent
pushes are batched diffs, not full snapshots** (see `TapestryUpdatedSchema` in
`shared/src/data-transfer/socket/types.ts`). The same subscribe/ack pattern backs
`'rtc-signaling-message'` (WebRTC signaling — collaborator cursors/voice), gated by
`isSignallerActivated`/`activateSignaller()`.

Everything arriving over the socket is **Zod-validated before use**
(`TapestryUpdatedSchema.parse(update)`, `RTCSignalingMessageSchema.parse(...)`) — don't
trust the wire payload's TS type alone. `SOCKET_PATH` and every event/payload type is
shared verbatim with the server via `shared/src/data-transfer/socket/types.ts` — if you
add a new socket event, add it there first so client and server stay in sync.

## Auth providers

Real providers today: **`ia` and `google` only** — the `VITE_AUTH_PROVIDER` Zod enum
in `config.ts` has exactly these two literals, and both the auth-service and
login-button lookup tables below only have entries for them.

`client/src/auth/index.tsx` is the provider-selection hub — a build-time switch, not a
runtime one:

```ts
type ProviderName = typeof config.authProvider   // from VITE_AUTH_PROVIDER, config.ts
const AUTH_SERVICES: Record<ProviderName, new () => AuthService> = { ia: IAAuthService, google: GoogleAuthService }
const LOGIN_BUTTONS: Record<ProviderName, ComponentType<LoginButtonProps>> = { ia: IALoginButton, google: GoogleLoginButton }
export const auth = new AUTH_SERVICES[config.authProvider]()
```

Each provider extends the abstract `AuthService<Credentials>` base
(`client/src/services/auth.ts`, an `Observable<AuthServiceState>` holding `accessToken`/
`autoRefreshTimeout`). Provider implementations: `client/src/auth/google/{service.ts,login-button.tsx}`,
`client/src/auth/internet-archive/{service.ts,login-button.tsx,login-dialog/index.tsx}`.
A shared `RegistrationModal` (username selection) lives in `auth/index.tsx` and is driven
by `auth.pendingRegistration` from the common base class.

**To add a new provider**: (1) add the literal to `VITE_AUTH_PROVIDER`'s Zod enum in
`config.ts`, (2) create `client/src/auth/<provider>/service.ts` extending `AuthService`,
(3) create `client/src/auth/<provider>/login-button.tsx`, (4) register both in the two
`Record<ProviderName, ...>` tables in `auth/index.tsx`, (5) plumb any new `VITE_*`/
server-side secret through `config.ts`, `Dockerfile.client*`, and the relevant
`docker-compose*.yml` build args — and add the matching server-side strategy (see
`tapestry-server-worker`'s Auth section; the server has its own, independent provider
map keyed by `authType`, not by this same `ProviderName`). See `tapestry-auth-providers`
for the complete checklist, including the OAuth authorization-code pattern most new
providers actually need.

## Build-time config (`client/src/config.ts`)

Single source of truth for all `import.meta.env` access — nothing else should read
`import.meta.env` directly. A Zod object schema is parsed once at module load,
`deepFreeze`d, and consumed via camelCase fields (`config.apiUrl`, `config.authProvider`,
never the raw `VITE_*` name):

```ts
const parsedConfig = deepFreeze(z.object({
  VITE_API_URL: z.string(),
  VITE_AUTH_PROVIDER: z.enum(['ia', 'google']).catch('google'),
  VITE_GOOGLE_CLIENT_ID: z.string(),
  VITE_BUG_REPORT_FORM_URL: z.string(),
  VITE_AI_CHAT_EXPIRES_IN: OptionalInt(3600),
  VITE_WEBPAGE_LOADER_TIMEOUT: OptionalInt(3, (s) => s.nonnegative()),
  VITE_WBM_SNAPSHOT_POLLING_PERIOD: OptionalInt(600),
  VITE_STUN_SERVER: z.string(),
  VITE_SENTRY_DSN: z.string().default(''),
}).transform((input) => ({ apiUrl: ..., authProvider: ..., /* camelCase fields */ })).safeParse(import.meta.env))
export const config = parsedConfig.data
```

**To add a new `VITE_*` var**: add it to the Zod object, add the camelCase field to the
`.transform(...)`, use `config.xxx` everywhere — then add it to `Dockerfile.client`
(`ARG VITE_XXX`) and the client build `args:` block in whichever `docker-compose*.yml`
you're using (note the compose-level env var name doesn't have to match the `VITE_`
name, e.g. compose `AUTH_PROVIDER` → build arg `VITE_AUTH_PROVIDER`, `SENTRY_DSN_CLIENT`
→ `VITE_SENTRY_DSN`). Vite inlines `VITE_*` at **build** time — per this user's own
Docker guidance, changing a value requires an actual image rebuild, not a container
restart; see `tapestry-local-dev-environment` for the rebuild command.

## Adding a component — idiomatic shape

Representative example: `client/src/components/tapestry-elements/item-toolbar/` (the
floating per-item toolbar) and its `change-thumbnail-button/` subfolder.

- **Folder-per-feature**, `index.tsx` as entry point, optional co-located
  `styles.module.css` (CSS Modules — `import styles from './styles.module.css'`,
  composed with `clsx(...)`), optional sibling `use-*.tsx` hook files for extracted logic.
- **Named exports**, not default (`export function ChangeThumbnailButton(...)`).
- **State lives in the parent**, dialogs/menus render conditionally as children next to
  their trigger (`{displayThumbnailDialog && <ChangeThumbnailDialog .../>}`), not as
  separately-mounted portals with their own visibility plumbing.
- **Reuse `core-client`'s primitives**: `IconButton`, `MenuItemButton`, `MenuItemToggle`,
  `Icon`, `SubmitOnBlurInput`, `SimpleModal`, `Button`, `Text`, `FilePicker`, `DropArea`,
  `LoadingSpinner` (`tapestry-core-client/src/components/lib/*`) — don't reimplement
  buttons/modals/icons.
- **Data access via typed store hooks + store commands**, not raw fetch/state:
  `useTapestryData(...)`/`useDispatch()` (from `client/src/pages/tapestry/tapestry-providers`)
  dispatching commands from `view-model/store-commands/*`; direct REST calls go through
  `resource(...)` (`client/src/services/rest-resources`); async side effects wrap
  `useAsyncAction`/`useAsync` (`tapestry-core-client/src/components/lib/hooks/*`) instead
  of hand-rolled loading/error `useState`.
- **Keyboard shortcuts** declared via `useKeyboardShortcuts({...}, [deps])`
  (`tapestry-core-client/src/components/lib/hooks/use-keyboard-shortcuts`), paired with a
  `shortcut="meta + alt + T"` prop on the corresponding `MenuItemButton` so it's visible
  in the UI, not just bound silently.
- **Menu composition is data-driven**: build an ordered array of menu-item literals
  (`buildToolbarMenu({...})`), resolved to UI via `useItemMenu(id, items, resolverFn)`
  (`tapestry-core-client/src/components/tapestry/hooks/use-item-menu`) — add a new
  toolbar entry by adding a literal + a resolver case, not by editing JSX layout.
- **No test files exist on the client** (`client`/`core-client`/`core`/`viewer` have zero
  `*.test.ts(x)` — only `server/src/__tests__/**` has tests). Don't add client tests
  unless explicitly asked; it's not the established convention here.

## Guardrails

1. **Respect the workspace boundary**: generic/reusable → `core-client`; app-specific
   (auth, live sockets, editor chrome) → `client`; pure schema → `core`. `viewer` must
   keep working with zero auth/socket dependency — don't leak `client`-only concerns
   into `core-client`'s defaults.
2. **New item type = multi-layer change.** Missing the `core-client` components-config
   entry is a compile error (by design) — don't work around it by casting.
3. **Adding a new auth provider is new work, not a config toggle** — see
   `tapestry-auth-providers` for the full client+server+schema checklist, and
   `tapestry-server-worker` for the matching server-side strategy map.
4. **Validate socket payloads with Zod on arrival** — don't trust the socket event's TS
   type alone, following `socket-manager.ts`'s existing pattern.
5. See `tapestry-server-worker` for the matching backend conventions, and
   `tapestry-local-dev-environment` for running/rebuilding the client locally
   (including the CSP gotchas around `VITE_*` build args).
