import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl, LaunchMode, canLaunchUrl;



const String baseUrl = "https://play.famobi.com/slice-rush"; // Замените на нужный сайт

// Простейший список фильтров URL (регулярки) для популярных рекламных доменов.
// Можно расширять/обновлять по желанию.
const List<String> FILT = [
  ".*doubleclick\\.net.*",
  ".*googleads\\.g\\.doubleclick\\.net.*",
  ".*googlesyndication\\.com.*",
  ".*googletagservices\\.com.*",
  ".*googletagmanager\\.com/gtm\\.js.*",
  ".*adservice\\.google.*",
  ".*adsystem\\.com.*",
  ".*adform\\.net.*",
  ".*taboola\\.com.*",
  ".*outbrain\\.com.*",
  ".*criteo\\.com.*",
  ".*zedo\\.com.*",
  ".*yandexad.*",
  ".*an.yandex\\.ru.*",
  ".*mc\\.yandex\\.ru/metrika.*",
  ".*betweendigital.*",
  ".*rtbhouse.*",
];

class WebContainerScreen2 extends StatefulWidget {
  const WebContainerScreen2({super.key});
  @override
  State<WebContainerScreen2> createState() => _WebContainerScreen2State();
}

class _WebContainerScreen2State extends State<WebContainerScreen2> {
  InAppWebViewController? webController;

  final List<ContentBlocker> contentBlockers = [];
  bool showSplash = true;
  bool showLoader = true;
  bool showAdBlockingOverlay = false; // Плашка "Waiting…"
  bool pageLoading = false;

  int keyCounter = 0;

  final List<String> _adCssSelectors = [
    '.ad', '.ads', '.adsbox', '.adsbygoogle', '.ad-banner', '.ad-container',
    '.advert', '.advertisement', '.ad-unit', '.sponsor', '.sponsored',
    '.promo', '.rewarded-ad', '.video-ad', '.floating-ad', '.sticky-ad',
    '.prestitial', '.interstitial', '#ad', '#ads', '#banner', '.banner',
    '.game-ad', '.start-screen-ad', '.preloader-ad',
    '[class*="ad-"]', '[class*="-ad"]', '[id*="ad-"]', '[id*="-ad"]',
    '[class*="promo"]', '[id*="promo"]',
    // cookie/consent/оверлеи
    '[class*="cookie"]','[id*="cookie"]','[class*="consent"]','[id*="consent"]',
    '.privacy-info','.notification'
  ];

  String get _adBlockCss => '''
${_adCssSelectors.join(',')} { display: none !important; visibility: hidden !important; opacity: 0 !important; }
html, body { overflow: auto !important; }
''';

  // Супер-жёсткий глобальный mute для HTMLMediaElement и WebAudio — во всех фреймах.
  String get _hardMuteScript => '''
(function(){
  if (window.__hardMuteInstalled) return;
  window.__hardMuteInstalled = true;

  // Подмена WebAudio API на dummy-контексты
  try {
    const DummyContext = function(){};
    const proto = DummyContext.prototype;
    const no = function(){ return null; };
    ['createBuffer','createBufferSource','createGain','createMediaElementSource','resume','suspend','close'].forEach(k => {
      try { proto[k] = no; } catch(e){}
    });
    Object.defineProperty(proto, 'destination', { get: function(){ return null; }});
    Object.defineProperty(proto, 'state', { get: function(){ return 'suspended'; }});
    Object.defineProperty(proto, 'currentTime', { get: function(){ return 0; }});
    Object.defineProperty(proto, 'sampleRate', { get: function(){ return 0; }});

    try { window.AudioContext = DummyContext; } catch(e){}
    try { window.webkitAudioContext = DummyContext; } catch(e){}
    try { window.OfflineAudioContext = DummyContext; } catch(e){}
    try { window.webkitOfflineAudioContext = DummyContext; } catch(e){}
  } catch(e){}

  // Функция принудительного mute для всех медиа
  function muteAllMedia(root) {
    try {
      var scope = root || document;
      var els = scope.querySelectorAll('video, audio');
      els.forEach(function(m) {
        try {
          m.muted = true;
          m.volume = 0.0;
          m.autoplay = false;
          m.removeAttribute('autoplay');
          if (m.paused === false && typeof m.pause === 'function') { m.pause(); }
          m.setAttribute('muted', '');
          try { m.setAttribute('controls', 'true'); } catch(_) {}
        } catch(_) {}
      });
    } catch(_) {}
  }

  // Перехват play(), чтобы ломать автоплей со звуком
  if (!window.__playHooked) {
    window.__playHooked = true;
    var origPlay = HTMLMediaElement.prototype.play;
    Object.defineProperty(HTMLMediaElement.prototype, 'play', {
      configurable: true,
      writable: true,
      value: function() {
        try { this.muted = true; this.volume = 0.0; this.setAttribute('muted',''); } catch(_){}
        // Возвращаем rejected Promise, чтобы любой autoplay со звуком не стартовал
        try { if (document.visibilityState !== 'visible') { return Promise.reject('Autoplay blocked'); } } catch(_){}
        // Даже если не rejected — медиа без звука
        try { if (typeof this.pause === 'function') this.pause(); } catch(_){}
        return Promise.reject('Autoplay with sound blocked by policy');
      }
    });
  }

  // Первичный mute и наблюдатели
  try { muteAllMedia(); } catch(_){}

  // Наблюдатель за мутациями DOM
  if (!window.__muteObserver) {
    window.__muteObserver = new MutationObserver(function(muts){
      try {
        muteAllMedia();
        muts.forEach(function(m){
          if (m.addedNodes) {
            m.addedNodes.forEach(function(n){
              try {
                if (n && n.querySelectorAll) muteAllMedia(n);
              } catch(_){}
            });
          }
        });
      } catch(_){}
    });
    try { window.__muteObserver.observe(document.documentElement || document.body, { childList: true, subtree: true }); } catch(_){}
  }

  // Периодический mute на всякий случай
  if (!window.__muteInterval) window.__muteInterval = setInterval(muteAllMedia, 1000);

  // Вложенные фреймы: попытка применить те же правила
  function applyToIframes() {
    document.querySelectorAll('iframe').forEach(function(fr){
      try {
        const w = fr.contentWindow;
        if (!w) return;
        try { w.AudioContext = function(){}; } catch(_){}
        try { w.webkitAudioContext = function(){}; } catch(_){}
        try { w.OfflineAudioContext = function(){}; } catch(_){}
        try { w.webkitOfflineAudioContext = function(){}; } catch(_){}
        try {
          if (!w.__playHooked) {
            w.__playHooked = true;
            var op = w.HTMLMediaElement && w.HTMLMediaElement.prototype && w.HTMLMediaElement.prototype.play;
            if (op) {
              w.HTMLMediaElement.prototype.play = function(){
                try { this.muted = true; this.volume = 0.0; this.setAttribute('muted',''); } catch(_){}
                try { if (typeof this.pause === 'function') this.pause(); } catch(_){}
                return Promise.reject('Autoplay with sound blocked (frame)');
              };
            }
          }
        } catch(_){}
        try {
          const frameDoc = fr.contentDocument || w.document;
          if (frameDoc) {
            const style = frameDoc.createElement('style');
            style.textContent = 'video,audio{volume:0 !important}';
            frameDoc.documentElement.appendChild(style);
            // Однократный mute
            try {
              frameDoc.querySelectorAll('video,audio').forEach(function(m){ m.muted = true; m.volume = 0.0; });
            } catch(_){}
          }
        } catch(_){}
      } catch(_){}
    });
  }

  try { applyToIframes(); } catch(_){}
  if (!window.__muteFrameInterval) window.__muteFrameInterval = setInterval(applyToIframes, 1500);

  console.log('[HardMute] Active');
})();
''';

  // Универсальный Ad Skipper: закрывает interstitial/overlay, жмёт Skip/Close, нулирует таймеры, убирает рекламные iframes, скипает прероллы
  String get _adSkipScript => '''
(function(){
  // Защитимся от повторной инициализации
  if (window.__adSkipperActive) return;
  window.__adSkipperActive = true;

  function looksAdLikeString(s) {
    if (!s) return false;
    s = s.toLowerCase();
    return /\\b(ad|ads|advert|advertisement|promo|sponsor|reward|interstitial|prestitial|overlay|popup|modal|video-ad|banner)\\b/.test(s)
           || s.includes('ad-') || s.includes('-ad') || s.includes('preroll') || s.includes('outstream');
  }

  function isAdElement(el) {
    if (!el) return false;
    const s = ((el.className||'') + ' ' + (el.id||'') + ' ' + (el.getAttribute('role')||'')).toLowerCase();
    return looksAdLikeString(s);
  }

  function forceCloseButtons() {
    const selectors = [
      '[class*="skip"]','[id*="skip"]','button[aria-label*="skip"]','[role="button"][class*="skip"]',
      '[class*="close"]','[id*="close"]','button[aria-label*="close"]','[role="button"][class*="close"]',
      '.ytp-ad-skip-button','button.ytp-ad-skip-button','button.ytp-ad-overlay-close-button',
      'button[title*="Skip"]','button[title*="Пропустить"]','[data-testid*="skip"]','[data-testid*="close"]'
    ];
    document.querySelectorAll(selectors.join(',')).forEach(function(b){
      try {
        const rect = b.getBoundingClientRect();
        if (rect.width === 0 || rect.height === 0) return;
        b.click();
      } catch(_){}
    });
  }

  function zeroAdTimers() {
    const cands = document.querySelectorAll('[class*="countdown"],[id*="countdown"],[class*="timer"],[id*="timer"],[class*="preroll"],[id*="preroll"]');
    cands.forEach(function(el){
      try { el.innerText = '0'; el.style.display = 'none'; } catch(_){}
    });
  }

  function hideAdOverlays() {
    const overlays = document.querySelectorAll([
      '.interstitial','.prestitial','.rewarded-ad','.video-ad','.ad-overlay','.ad-modal',
      '.modal','.popup','.lightbox','.overlay','.backdrop','.blocker',
      '[class*="interstitial"]','[class*="prestitial"]','[class*="reward"]',
      '[class*="overlay"]','[class*="modal"]','[id*="modal"]','[id*="overlay"]'
    ].join(','));
    overlays.forEach(function(el){
      try {
        if (isAdElement(el)) {
          el.style.setProperty('display','none','important');
          el.style.setProperty('visibility','hidden','important');
          el.style.setProperty('opacity','0','important');
          el.setAttribute('aria-hidden','true');
        }
      } catch(_){}
    });

    // Разблокируем скролл
    try {
      document.documentElement.style.overflow = 'auto';
      document.body.style.overflow = 'auto';
      document.body.style.position = 'static';
      document.body.style.removeProperty('pointer-events');
    } catch(_){}
  }

  function skipVideoAds() {
    document.querySelectorAll('video').forEach(function(v){
      try {
        const parent = v.closest('.ad, .ads, .advert, .advertisement, .video-ad, [class*="ad-"], [class*="-ad"], [id*="ad-"], [id*="-ad"], [class*="promo"], [id*="promo"]');
        if (parent) {
          v.muted = true; v.volume = 0;
          if (!isNaN(v.duration) && isFinite(v.duration) && v.duration > 0) {
            v.currentTime = Math.max(v.duration - 0.25, 0);
          }
          if (typeof v.pause === 'function') { v.pause(); }
          parent.style.setProperty('display','none','important');
        }
      } catch(_){}
    });
  }

  function removeAdIframes() {
    document.querySelectorAll('iframe').forEach(function(fr){
      try {
        const src = (fr.src||'').toLowerCase();
        const nm = (fr.name||'').toLowerCase();
        const id = (fr.id||'').toLowerCase();
        const cls = (fr.className||'').toLowerCase();
        const looksAd = /ad|advert|promo|sponsor|doubleclick|gdoubleclick|googlesyndication|taboola|outbrain|criteo|adservice|adform|zedo/.test(src+nm+id+cls);
        if (looksAd) fr.remove();
      } catch(_){}
    });
  }

  function runAll() {
    forceCloseButtons();
    hideAdOverlays();
    zeroAdTimers();
    skipVideoAds();
    removeAdIframes();
  }

  // Первичный прогон
  runAll();

  // Реакция на мутации
  if (!window.__adSkipperObserver) {
    window.__adSkipperObserver = new MutationObserver(runAll);
    try { window.__adSkipperObserver.observe(document.documentElement || document.body, { childList: true, subtree: true }); } catch(_){}
  }

  // Периодический прогон (динамика/SPA)
  if (!window.__adSkipperInterval) {
    window.__adSkipperInterval = setInterval(runAll, 1000);
  }

  console.log('[AdSkipper] Active');
})();
''';

  @override
  void initState() {
    super.initState();

    // Инициализируем блокировщики контента
    for (final adUrlFilter in FILT) {
      contentBlockers.add(
        ContentBlocker(
          trigger: ContentBlockerTrigger(urlFilter: adUrlFilter),
          action:  ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
        ),
      );
    }

    // CSS-скрытие рекламы/оверлеев
    contentBlockers.add(
      ContentBlocker(
        trigger:  ContentBlockerTrigger(urlFilter: '.*'),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.CSS_DISPLAY_NONE,
          selector: _adCssSelectors.join(','),
        ),
      ),
    );

    // Короткий сплэш
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        showSplash = false;
        showLoader = true;
      });
      // Скрыть основной лоадер через 10 сек. или по факту первой загрузки
      Future.delayed(const Duration(seconds: 10), () {
        if (!mounted) return;
        setState(() => showLoader = false);
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> tryStopLoading(InAppWebViewController c) async {
    try { await c.stopLoading(); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (showSplash) const _Splash(),
            if (!showSplash)
              Container(
                color: Colors.black,
                child: Stack(
                  children: [
                    InAppWebView(
                      key: ValueKey(keyCounter),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        disableDefaultErrorPage: true,
                        contentBlockers: contentBlockers,
                        mediaPlaybackRequiresUserGesture: true,
                        allowsInlineMediaPlayback: true,
                        allowsPictureInPictureMediaPlayback: true,
                        useOnDownloadStart: true,
                        javaScriptCanOpenWindowsAutomatically: true,
                        useShouldOverrideUrlLoading: true,
                        supportMultipleWindows: true,
                        transparentBackground: false,
                        allowsBackForwardNavigationGestures: true,
                        preferredContentMode: UserPreferredContentMode.MOBILE,
                        // важно: скрипты будут также встраиваться во фреймы
                        // (для версии 6.x+ flutter_inappwebview — включено по умолчанию; если есть опция forMainFrameOnly — установить false)
                      ),
                      initialUserScripts: UnmodifiableListView<UserScript>([
                        UserScript(
                          source: """
                            try {
                              var style = document.createElement('style');
                              style.type = 'text/css';
                              style.appendChild(document.createTextNode(`${_adBlockCss}`));
                              document.documentElement.appendChild(style);
                            } catch(e) { console.log('inject css error', e); }
                          """,
                          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                        ),
                        // Важно: мьют сначала — чтобы ни один звук не прорвался
                        UserScript(
                          source: _hardMuteScript,
                          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                        ),
                        // AdSkipper подключаем в конце документа
                        UserScript(
                          source: _adSkipScript,
                          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
                        ),
                      ]),
                      initialUrlRequest: URLRequest(url: WebUri(baseUrl)),
                      onWebViewCreated: (c) {
                        webController = c;
                      },
                      onLoadStart: (c, u) async {
                        pageLoading = true;
                        setState(() => showAdBlockingOverlay = true);
                      },
                      onLoadStop: (c, u) async {
                        pageLoading = false;
                        try {
                          await c.injectCSSCode(source: _adBlockCss);
                          await c.evaluateJavascript(source: _hardMuteScript);
                          await c.evaluateJavascript(source: _adSkipScript);
                          await c.evaluateJavascript(source: "console.log('Page loaded');");
                        } catch (_) {}

                        if (mounted) {
                          setState(() => showAdBlockingOverlay = false);
                        }
                      },
                      onReceivedError: (c, req, err) async {
                        if (mounted) {
                          setState(() => showAdBlockingOverlay = false);
                        }
                      },
                      shouldOverrideUrlLoading: (c, action) async {
                        final uri = action.request.url;
                        if (uri == null) return NavigationActionPolicy.ALLOW;

                        final scheme = uri.scheme.toLowerCase();

                        if (scheme == 'mailto') {
                          await openEmail(uri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (scheme == 'tel') {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                          return NavigationActionPolicy.CANCEL;
                        }

                        // Блокировка не http/https
                        if (scheme != 'http' && scheme != 'https') {
                          return NavigationActionPolicy.CANCEL;
                        }

                        // При каждой навигации показываем overlay “Waiting…”
                        pageLoading = true;
                        setState(() => showAdBlockingOverlay = true);

                        return NavigationActionPolicy.ALLOW;
                      },
                      onCreateWindow: (c, req) async {
                        final uri = req.request.url;
                        if (uri == null) return false;

                        final scheme = uri.scheme.toLowerCase();
                        if (scheme == 'mailto') {
                          await openEmail(uri);
                          return false;
                        }
                        if (scheme == 'tel') {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                          return false;
                        }

                        if (scheme == 'http' || scheme == 'https') {
                          pageLoading = true;
                          setState(() => showAdBlockingOverlay = true);
                          c.loadUrl(urlRequest: URLRequest(url: uri));
                        }
                        return false;
                      },
                      onDownloadStartRequest: (c, req) async {
                        await launchUrl(req.url, mode: LaunchMode.externalApplication);
                      },
                      onConsoleMessage: (controller, msg) async {
                        // Можно тут ловить любые "savedata:" сигналы, если нужно
                      },
                    ),




                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/* =========================
   Вспомогательные виджеты
   ========================= */

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(width: 48, height: 48, child: CircularProgressIndicator(color: Colors.white)),
          SizedBox(height: 16),
          Text("Loading…", style: TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}

/* =========================
   Утилиты
   ========================= */

Future<void> openEmail(Uri mailtoUri) async {
  try {
    await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint("openEmail error: $e");
  }
}