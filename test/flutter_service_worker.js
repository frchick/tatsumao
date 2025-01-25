'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"assets/AssetManifest.bin": "ecbe75f62c7ce05b9f57cbdb541636aa",
"assets/AssetManifest.json": "8048c79f542e96ffc31d22740310ab1b",
"assets/assets/dog_icon/000.png": "6de369796a602171fd474b5799a184ca",
"assets/assets/dog_icon/001.png": "19ccb2169baed504959e128359ace6e9",
"assets/assets/dog_icon/002.png": "746a2844e19179ad904358ab1af13cdc",
"assets/assets/dog_icon/003.png": "677d79d7ecf23bedb462be3c405b17ab",
"assets/assets/dog_icon/004.png": "689819c12b808ca37ff2ce1882fe85d3",
"assets/assets/dog_icon/005.png": "21673e001d4302c16e7874a1d09166eb",
"assets/assets/dog_icon/998.png": "74e5ada3e6637d689596aaf4e0dc3c3a",
"assets/assets/dog_icon/999.png": "1e2783a61153d2e50d50cdf25d05d1fa",
"assets/assets/fonts/KosugiMaru-Regular.ttf": "f0f9ba6949b53fa1ec3a5c49e508bcda",
"assets/assets/member_icon/loading.png": "1e93ed1e0b8eaade6335bf053209f5f3",
"assets/assets/misc/deer_icon0.png": "14c1ab97d992b807fa1341565d4871dd",
"assets/assets/misc/deer_icon1.png": "b11b40b65859050f2313a4c74839f761",
"assets/assets/misc/deer_icon2.png": "26815b8d7832dda20218151fe44916cd",
"assets/assets/misc/tatsu_pos_icon.png": "4ee592b3815e6f57b6b19e115f4b3643",
"assets/assets/misc/tatsu_pos_icon_gray.png": "28c17a1d6b526cc223fb146d8d6d1def",
"assets/assets/misc/tatsu_pos_icon_green.png": "aa04f5fb00e567e6ce7a74a5158afe9e",
"assets/FontManifest.json": "b9e95d9f8863c8d3dc83fa8bf4b2387a",
"assets/fonts/MaterialIcons-Regular.otf": "bf54e2cf98b50d0c4ccd1a4ab38e5001",
"assets/NOTICES": "740e3398cd0953c9fbeaf06d5bded404",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "89ed8f4e49bcdfc0b5bfc9b24591e347",
"assets/shaders/ink_sparkle.frag": "f8b80e740d33eb157090be4e995febdf",
"canvaskit/canvaskit.js": "bbf39143dfd758d8d847453b120c8ebb",
"canvaskit/canvaskit.wasm": "42df12e09ecc0d5a4a34a69d7ee44314",
"canvaskit/chromium/canvaskit.js": "96ae916cd2d1b7320fff853ee22aebb0",
"canvaskit/chromium/canvaskit.wasm": "be0e3b33510f5b7b0cc76cc4d3e50048",
"canvaskit/skwasm.js": "95f16c6690f955a45b2317496983dbe9",
"canvaskit/skwasm.wasm": "1a074e8452fe5e0d02b112e22cdcf455",
"canvaskit/skwasm.worker.js": "51253d3321b11ddb8d73fa8aa87d3b15",
"favicon.png": "cf19c8f48d00dbb7a0e7b85e9048cc03",
"flutter.js": "6b515e434cea20006b3ef1726d2c8894",
"icons/Icon-192.png": "2e134994614df3b1640c8c415bcdeb9d",
"icons/Icon-512.png": "6978875636d76d5e7446b82dfea2b46b",
"icons/Icon-maskable-192.png": "6299bee70be6bf2fd8871b42feea5c25",
"icons/Icon-maskable-512.png": "ee2ab98d17f5eb56f613c04946d3eeeb",
"index.html": "e56f4ce791a2a562a9f896fbadb02e9e",
"/": "e56f4ce791a2a562a9f896fbadb02e9e",
"main.dart.js": "00e199da7b06ba0f766922b52de35733",
"manifest.json": "8a0282dbeb1ca91a76f0b8bf1d49e064",
"version.json": "3add4a5187e2c74d5702df47b5b0eba5"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"assets/AssetManifest.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
