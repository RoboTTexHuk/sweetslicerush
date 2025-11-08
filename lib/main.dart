import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:appsflyer_sdk/appsflyer_sdk.dart' as zax_fly;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Если у вас есть свой список блокировок в F.dart — импортируйте его и замените FILT.
// import 'F.dart';
// Для автономного примера оставим пустой список:
const List<String> FILT = [];

// ============== НАСТРОЙКИ/КОНСТАНТЫ ==============

const String baseUrl = "https://gm.sweetslicerush.online/";
const String fallbackUrl = "https://play.famobi.com/slice-rush";

const String appsFlyerDevKey = "qsBLmy7dAXDQhowM8V3ca4";
const String appsFlyerAppId = "6754987923"; // iOS App ID (без "id")

// ============== МОДЕЛИ/СЕРВИСЫ ==============

class DeviceData {
  final String? deviceId;
  final String? sessionId;
  final String? platformType;
  final String? osVersion;
  final String? language;
  final String? timezone;
  final bool notificationsEnabled;
  final String? appVersion;
  final String? bundleId;

  const DeviceData({
    this.deviceId,
    this.sessionId,
    this.platformType,
    this.osVersion,
    this.language = 'en',
    this.timezone = 'UTC',
    this.notificationsEnabled = true,
    this.appVersion,
    this.bundleId,
  });

  DeviceData copyWith({
    String? deviceId,
    String? sessionId,
    String? platformType,
    String? osVersion,
    String? language,
    String? timezone,
    bool? notificationsEnabled,
    String? appVersion,
    String? bundleId,
  }) {
    return DeviceData(
      deviceId: deviceId ?? this.deviceId,
      sessionId: sessionId ?? this.sessionId,
      platformType: platformType ?? this.platformType,
      osVersion: osVersion ?? this.osVersion,
      language: language ?? this.language,
      timezone: timezone ?? this.timezone,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      appVersion: appVersion ?? this.appVersion,
      bundleId: bundleId ?? this.bundleId,
    );
  }
}

class TrackingManager {
  Map<String, dynamic>? conversionData;
  String trackingId = '';

  late zax_fly.AppsflyerSdk _appsFlyerSdk;
  bool initialized = false;

  Future<void> init({
    required String devKey,
    required String appId,
    required bool isDebug,
  }) async {
    final options = {
      "afDevKey": devKey,
      "afAppId": appId,
      "isDebug": isDebug,
    };
    _appsFlyerSdk = zax_fly.AppsflyerSdk(options);

    _appsFlyerSdk.onInstallConversionData((res) {
      try {
        conversionData = Map<String, dynamic>.from(res);
      } catch (_) {
        conversionData = {"raw": res};
      }
    });

    _appsFlyerSdk.onAppOpenAttribution((res) {
      conversionData ??= {};
      conversionData!['appOpenAttribution'] = res;
    });

    await _appsFlyerSdk.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
    );

    _appsFlyerSdk.startSDK(
      onSuccess: () => debugPrint("AppsFlyer started"),
      onError: (int c, String m) => debugPrint("AppsFlyer error $c: $m"),
    );

    trackingId = await _appsFlyerSdk.getAppsFlyerUID() ?? '';
    initialized = true;
  }
}

// ============== ГЛОБАЛЬНЫЕ ДАННЫЕ ==============

DeviceData deviceData = const DeviceData();

String? fcmToken;

// ============== ХЕЛПЕРЫ ССЫЛОК ==============

bool isPlainEmail(Uri uri) {
  final s = uri.toString();
  final emailRegex = RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$");
  return (uri.scheme.isEmpty || uri.scheme == 'about') && emailRegex.hasMatch(s);
}

Uri convertToMailto(Uri uri) {
  if (uri.scheme.isEmpty) {
    return Uri.parse("mailto:${uri.toString()}");
  }
  return uri;
}

bool isPlatformLink(Uri uri) {
  final host = uri.host.toLowerCase();
  final scheme = uri.scheme.toLowerCase();
  if (['tg', 'whatsapp', 'vk', 'fb', 'instagram', 'twitter', 'vkontakte'].contains(scheme)) {
    return true;
  }
  if (host.contains('play.google.com') || host.contains('apps.apple.com')) {
    return true;
  }
  return false;
}

Uri convertToWebUri(Uri uri) {
  if (uri.host.contains('play.google.com') || uri.host.contains('apps.apple.com')) {
    return uri;
  }
  if (uri.scheme == 'tg') {
    if (uri.host == 'resolve' && uri.queryParameters['domain'] != null) {
      return Uri.parse('https://t.me/${uri.queryParameters['domain']}');
    }
    return Uri.parse('https://t.me/');
  }
  if (uri.scheme == 'whatsapp') {
    return Uri.parse('https://wa.me/');
  }
  return uri;
}

Future<void> openEmail(Uri uri) async {
  final can = await canLaunchUrl(uri);
  if (can) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

Future<void> openInBrowser(Uri uri) async {
  await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
    webViewConfiguration: const WebViewConfiguration(enableJavaScript: true),
  );
}

// ============== СБОР РЕАЛЬНЫХ ДАННЫХ УСТРОЙСТВА/ПРИЛОЖЕНИЯ ==============

Future<DeviceData> collectRealDeviceData() async {
  String? platformType;
  String? osVersion;
  String? deviceId;
  String? language;
  String? timezone;
  String? appVersion;
  String? bundleId;

  final deviceInfo = DeviceInfoPlugin();
  if (Platform.isAndroid) {
    final info = await deviceInfo.androidInfo;
    platformType = "android";
    osVersion = "Android ${info.version.release} (SDK ${info.version.sdkInt})";
    deviceId = info.id ?? info.fingerprint ?? info.hardware ?? "android-unknown";
  } else if (Platform.isIOS) {
    final info = await deviceInfo.iosInfo;
    platformType = "ios";
    osVersion = "${info.systemName} ${info.systemVersion}";
    deviceId = info.identifierForVendor;
  } else {
    final info = await deviceInfo.deviceInfo;
    platformType = info.data['systemName']?.toString().toLowerCase() ?? Platform.operatingSystem;
    osVersion = info.data['systemVersion']?.toString() ?? Platform.operatingSystemVersion;
    deviceId = info.data['serialNumber']?.toString() ?? "device-unknown";
  }

  final locale = PlatformDispatcher.instance.locale;
  language = locale.toLanguageTag();

  try {
    timezone = "UTC";
  } catch (_) {
    timezone = "UTC";
  }

  final pInfo = await PackageInfo.fromPlatform();
  appVersion = pInfo.version;
  bundleId = pInfo.packageName;

  final sessionId = "sess_${DateTime.now().millisecondsSinceEpoch}";
  const notificationsEnabled = true;

  return DeviceData(
    deviceId: deviceId,
    sessionId: sessionId,
    platformType: platformType,
    osVersion: osVersion,
    language: language,
    timezone: timezone,
    notificationsEnabled: notificationsEnabled,
    appVersion: appVersion,
    bundleId: bundleId,
  );
}

// ============== КАСТОМНЫЙ ЛОАДЕР ==============

class CustomLoader extends StatefulWidget {
  const CustomLoader({super.key});

  @override
  State<CustomLoader> createState() => _CustomLoaderState();
}

class _CustomLoaderState extends State<CustomLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E88E5),
      alignment: Alignment.center,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: const Size(160, 160),
            painter: _LoaderPainter(progress: _controller.value),
          );
        },
      ),
    );
  }
}

class _LoaderPainter extends CustomPainter {
  final double progress;
  _LoaderPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paintCircle = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..isAntiAlias = true;

    final paintOval = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..isAntiAlias = true;

    final paintBar = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 8;

    canvas.drawCircle(center, r, paintCircle);

    final rect = Rect.fromCenter(center: center, width: r * 1.6, height: r * 1.0);
    final angle = progress * 2 * math.pi;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawOval(rect, paintOval);
    canvas.restore();

    final dashSweep = math.pi * 1.2;
    final start = angle;
    final path = Path()
      ..addArc(Rect.fromCircle(center: center, radius: r * 0.7), start, dashSweep);
    final pathPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, pathPaint);

    final barLen = r * 1.8;
    final barAngle = -angle * 1.2;
    final p1 = center + Offset(math.cos(barAngle), math.sin(barAngle)) * (barLen / 2);
    final p2 = center - Offset(math.cos(barAngle), math.sin(barAngle)) * (barLen / 2);
    paintBar.strokeWidth = 6;
    paintBar.strokeCap = StrokeCap.round;
    canvas.drawLine(p1, p2, paintBar);
  }

  @override
  bool shouldRepaint(covariant _LoaderPainter oldDelegate) => oldDelegate.progress != progress;
}

// ============== ПРИЛОЖЕНИЕ ==============

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  deviceData = await collectRealDeviceData();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SweetSliceRush',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const WebContainerScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ============== Fallback экран с InAppWebView и contentBlockers ==============

class FallbackScreen extends StatefulWidget {
  final List<ContentBlocker> contentBlockers;
  const FallbackScreen({super.key, required this.contentBlockers});

  @override
  State<FallbackScreen> createState() => _FallbackScreenState();
}

class _FallbackScreenState extends State<FallbackScreen> {
  InAppWebViewController? _controller;
  bool _showLoader = true;
@override
  void initState() {
  print("Loadenew ");
    super.initState();
  }
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,

        body: Stack(
          children: [
            InAppWebView(
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                disableDefaultErrorPage: true,
                contentBlockers: widget.contentBlockers,
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
              initialUrlRequest: URLRequest(url: WebUri(fallbackUrl)),
              onWebViewCreated: (c) => _controller = c,
              onLoadStop: (c, url) async {
                if (mounted) setState(() => _showLoader = false);
              },
              onReceivedError: (c, req, err) async {
                if (mounted) setState(() => _showLoader = false);
              },
              shouldOverrideUrlLoading: (c, action) async {
                final uri = action.request.url;
                if (uri == null) return NavigationActionPolicy.ALLOW;

                if (isPlainEmail(uri)) {
                  final mailtoUri = convertToMailto(uri);
                  await openEmail(mailtoUri);
                  return NavigationActionPolicy.CANCEL;
                }

                final scheme = uri.scheme.toLowerCase();

                if (scheme == 'mailto') {
                  await openEmail(uri);
                  return NavigationActionPolicy.CANCEL;
                }

                if (scheme == 'tel') {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                  return NavigationActionPolicy.CANCEL;
                }

                if (isPlatformLink(uri)) {
                  final webUri = convertToWebUri(uri);
                  if (webUri.scheme == 'http' || webUri.scheme == 'https') {
                    await openInBrowser(webUri);
                  } else {
                    try {
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } else if (webUri != uri &&
                          (webUri.scheme == 'http' || webUri.scheme == 'https')) {
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
                  await openEmail(mailtoUri);
                  return false;
                }

                final scheme = uri.scheme.toLowerCase();

                if (scheme == 'mailto') {
                  await openEmail(uri);
                  return false;
                }

                if (scheme == 'tel') {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                  return false;
                }

                if (isPlatformLink(uri)) {
                  final webUri = convertToWebUri(uri);
                  if (webUri.scheme == 'http' || webUri.scheme == 'https') {
                    await openInBrowser(webUri);
                  } else {
                    try {
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } else if (webUri != uri &&
                          (webUri.scheme == 'http' || webUri.scheme == 'https')) {
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
                await openInBrowser(req.url);
              },
            ),
            if (_showLoader)
              const Positioned.fill(
                child: IgnorePointer(
                  child: CustomLoader(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============== Главный экран с WebView ==============

class WebContainerScreen extends StatefulWidget {
  const WebContainerScreen({super.key});
  @override
  State<WebContainerScreen> createState() => _WebContainerScreenState();
}

class _WebContainerScreenState extends State<WebContainerScreen> {
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
    initTracking();

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

    // Запуск отправки трекинга через 6 сек (не влияет на savedata)
    _sendTrackingTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) {
        sendTrackingData();
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

  Future<void> initTracking() async {
    try {
      await trackingManager.init(
        devKey: appsFlyerDevKey,
        appId: appsFlyerAppId,
        isDebug: true,
      );
    } catch (e) {
      debugPrint("AppsFlyer init error: $e");
    }
  }

  Future<void> sendTrackingData() async {
    final data = {
      "content": {
        "af_data": trackingManager.conversionData,
        "af_id": trackingManager.trackingId,
        "fb_app_name": "sweetslicerush",
        "app_name": "sweetslicerush",
        "deep": null,
        "bundle_identifier": deviceData.bundleId ?? "no_bundle",
        "app_version": deviceData.appVersion ?? "0.0.0",
        "apple_id": appsFlyerAppId,
        "fcm_token": " ",
        "device_id": deviceData.deviceId ?? "no_device",
        "instance_id": deviceData.sessionId ?? "no_instance",
        "platform": deviceData.platformType ?? "no_type",
        "os_version": deviceData.osVersion ?? "no_os",
        "language": deviceData.language ?? "en",
        "timezone": deviceData.timezone ?? "UTC",
        "push_enabled": deviceData.notificationsEnabled,
        "useruid": trackingManager.trackingId,
      },
    };
    final jsonString = jsonEncode(data);
    debugPrint("SendRawData: $jsonString");
    if (webController != null) {
      try {
        await webController!.evaluateJavascript(
          source: "sendRawData(${jsonEncode(jsonString)});",
        );
      } catch (e) {
        debugPrint("evaluateJavascript sendRawData error: $e");
      }
    }
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
                      initialUrlRequest: URLRequest(url: WebUri(baseUrl)),
                      onWebViewCreated: (c) {
                        webController = c;

                        webController!.addJavaScriptHandler(
                          handlerName: 'onServerResponse',
                          callback: (args) {
                            debugPrint("JS args: $args");
                            try {
                              final saved = args.isNotEmpty
                                  ? args[0]['savedata']?.toString().toLowerCase()
                                  : null;
                        print("Save data "+args[0]['savedata'].toString());
                              if (saved == "true") {
                                savedataReceived = true;
                                if (mounted) {
                                  hasShownInitialLoader = true;
                                  _savedataWaitTimer?.cancel();
                                  _fallbackHideLoader12sTimer?.cancel();
                                  setState(() => showLoader = false);
                                }
                              }
                            } catch (e) {
                              debugPrint("onServerResponse parse error: $e");
                            }
                            return args.toString();
                          },
                        );
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
                          sendTrackingData();

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