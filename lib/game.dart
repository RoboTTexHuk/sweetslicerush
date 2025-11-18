import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl, LaunchMode, canLaunchUrl;

import 'main.dart';

class WebContainerScreen2 extends StatefulWidget {
  const WebContainerScreen2({super.key});
  @override
  State<WebContainerScreen2> createState() => _WebContainerScreen2State();
}

class _WebContainerScreen2State extends State<WebContainerScreen2> {
  InAppWebViewController? webController;
  final List<ContentBlocker> contentBlockers = [];

  bool showSplash = true;
  bool showLoader = true; // показываем только один раз
  bool hasShownInitialLoader = false; // первичный лоадер уже был?
  bool savedataReceived = false; // пришел ли savedata от WebView?
  int keyCounter = 0;

  final trackingManager = TrackingManager();
  Timer? _sendTrackingTimer;
  Timer? _fallbackHideLoader12sTimer; // страховка скрыть лоадер через 12 сек
  Timer? _savedataWaitTimer; // 6-секундный таймер ожидания savedata

  @override
  void initState() {
    super.initState();


    for (final adUrlFilter in FILT) {
      contentBlockers.add(
        ContentBlocker(
          trigger: ContentBlockerTrigger(urlFilter: adUrlFilter),
          action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
        ),
      );
    }

    contentBlockers.add(
      ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: ".cookie", resourceType: [
          ContentBlockerTriggerResourceType.RAW
        ]),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.BLOCK,
          selector: ".notification",
        ),
      ),
    );

    contentBlockers.add(
      ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: ".cookie", resourceType: [
          ContentBlockerTriggerResourceType.RAW
        ]),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.CSS_DISPLAY_NONE,
          selector: ".privacy-info",
        ),
      ),
    );

    contentBlockers.add(
      ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: ".*"),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.CSS_DISPLAY_NONE,
          selector: ".banner, .banners, .ads, .ad, .advert",
        ),
      ),
    );

    // Сплэш 2 сек
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => showSplash = false);

      // Включаем первичный лоадер, если еще не показывали
      if (!hasShownInitialLoader) {
        setState(() => showLoader = true);

        // Страховка: скрыть лоадер через 12 сек (только на первую загрузку)
        _fallbackHideLoader12sTimer = Timer(const Duration(seconds: 12), () {
          if (mounted) setState(() => showLoader = false);
        });
      }
    });


  }

  @override
  void dispose() {
    _sendTrackingTimer?.cancel();
    _fallbackHideLoader12sTimer?.cancel();
    _savedataWaitTimer?.cancel();
    super.dispose();
  }





  Future<void> tryStopLoading(InAppWebViewController c) async {
    try {
      await c.stopLoading();
    } catch (_) {}
  }

  Future<void> setupNotificationHandler() async {
    return;
  }

  void _startSavedataWaitTimerIfNeeded() {
    // Запускаем 6-секундный таймер ожидания savedata только один раз, на первой загрузке.
    if (_savedataWaitTimer != null || hasShownInitialLoader) return;

    _savedataWaitTimer = Timer(const Duration(seconds: 6), () {
      // Если за 6 секунд savedata так и не получили — переходим на FallbackScreen
      if (mounted && !savedataReceived) {
        hasShownInitialLoader = true;
        showLoader = false;
        _fallbackHideLoader12sTimer?.cancel();

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => FallbackScreen(contentBlockers: contentBlockers),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    setupNotificationHandler();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (showSplash) const CustomLoader(),
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
                        mediaPlaybackRequiresUserGesture: false,
                        allowsInlineMediaPlayback: true,
                        allowsPictureInPictureMediaPlayback: true,
                        useOnDownloadStart: true,
                        javaScriptCanOpenWindowsAutomatically: true,
                        useShouldOverrideUrlLoading: true,
                        supportMultipleWindows: true,
                        transparentBackground: false,
                        allowsBackForwardNavigationGestures: true,
                      ),
                      initialUrlRequest: URLRequest(url: WebUri("https://play.famobi.com/slice-rush")),
                      onWebViewCreated: (c) {
                        webController = c;

                      },
                      onLoadStart: (c, u) async {
                        final uri = u;
                        if (uri != null) {
                          if (isPlainEmail(uri)) {
                            await tryStopLoading(c);
                            final mailtoUri = convertToMailto(uri);
                            if (mounted) await openEmail(mailtoUri);
                            return;
                          }
                          final scheme = uri.scheme.toLowerCase();
                          if (scheme != 'http' && scheme != 'https') {
                            await tryStopLoading(c);
                          }
                        }
                      },
                      onLoadStop: (c, u) async {
                        try {
                          await c.evaluateJavascript(source: "console.log('Portal loaded!');");
                          debugPrint("Load my data $u");
                        } catch (_) {}

                        if (mounted) {
                          await sendDeviceInfo();


                          // Стартуем 6-секундное ожидание savedata только один раз,
                          // на самой первой успешной загрузке.
                          _startSavedataWaitTimerIfNeeded();

                          // Если к этому моменту savedata уже прилетел (редко), снимем лоадер.
                          if (!hasShownInitialLoader && savedataReceived) {
                            hasShownInitialLoader = true;
                            _savedataWaitTimer?.cancel();
                            _fallbackHideLoader12sTimer?.cancel();
                            setState(() => showLoader = false);
                          }
                        }
                      },
                      onReceivedError: (c, req, err) async {
                        debugPrint("Web error: $err");
                        if (mounted && !hasShownInitialLoader) {
                          hasShownInitialLoader = true;
                          _savedataWaitTimer?.cancel();
                          _fallbackHideLoader12sTimer?.cancel();
                          setState(() => showLoader = false);
                        }
                      },
                      shouldOverrideUrlLoading: (c, action) async {
                        final uri = action.request.url;
                        if (uri == null) return NavigationActionPolicy.ALLOW;

                        if (isPlainEmail(uri)) {
                          final mailtoUri = convertToMailto(uri);
                          if (mounted) await openEmail(mailtoUri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        final scheme = uri.scheme.toLowerCase();

                        if (scheme == 'mailto') {
                          if (mounted) await openEmail(uri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (scheme == 'tel') {
                          if (mounted) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (isPlatformLink(uri)) {
                          final webUri = convertToWebUri(uri);
                          if (webUri.scheme == 'http' || webUri.scheme == 'https') {
                            if (mounted) await openInBrowser(webUri);
                          } else {
                            try {
                              if (await canLaunchUrl(uri) && mounted) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } else if (webUri != uri &&
                                  (webUri.scheme == 'http' || webUri.scheme == 'https') &&
                                  mounted) {
                                await openInBrowser(webUri);
                              }
                            } catch (_) {}
                          }
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (scheme != 'http' && scheme != 'https') {
                          return NavigationActionPolicy.CANCEL;
                        }

                        return NavigationActionPolicy.ALLOW;
                      },
                      onCreateWindow: (c, req) async {
                        final uri = req.request.url;
                        if (uri == null) return false;

                        if (isPlainEmail(uri)) {
                          final mailtoUri = convertToMailto(uri);
                          if (mounted) await openEmail(mailtoUri);
                          return false;
                        }

                        final scheme = uri.scheme.toLowerCase();

                        if (scheme == 'mailto') {
                          if (mounted) await openEmail(uri);
                          return false;
                        }

                        if (scheme == 'tel') {
                          if (mounted) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                          return false;
                        }

                        if (isPlatformLink(uri)) {
                          final webUri = convertToWebUri(uri);
                          if (webUri.scheme == 'http' || webUri.scheme == 'https') {
                            if (mounted) await openInBrowser(webUri);
                          } else {
                            try {
                              if (await canLaunchUrl(uri) && mounted) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } else if (webUri != uri &&
                                  (webUri.scheme == 'http' || webUri.scheme == 'https') &&
                                  mounted) {
                                await openInBrowser(webUri);
                              }
                            } catch (_) {}
                          }
                          return false;
                        }

                        if (scheme == 'http' || scheme == 'https') {
                          c.loadUrl(urlRequest: URLRequest(url: uri));
                        }
                        return false;
                      },
                      onDownloadStartRequest: (c, req) async {
                        if (mounted) await openInBrowser(req.url);
                      },
                    ),

                    // Оверлей-лоадер, который показывается только на первом открытии
                    if (showLoader)
                      const Positioned.fill(
                        child: IgnorePointer(child: CustomLoader()),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> sendDeviceInfo() async {
    debugPrint(
      "sendDeviceInfo: deviceId=${deviceData.deviceId}, os=${deviceData.osVersion}, "
          "platform=${deviceData.platformType}, lang=${deviceData.language}, tz=${deviceData.timezone}, "
          "bundle=${deviceData.bundleId}, appVersion=${deviceData.appVersion}",
    );
  }
}