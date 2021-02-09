import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:better_socket/better_socket.dart';

import '../logger.dart';
import '../sip_ua_helper.dart';

typedef OnMessageCallback = void Function(dynamic msg);
typedef OnCloseCallback = void Function(int code, String reason);
typedef OnOpenCallback = void Function();

class WebSocketImpl {
  WebSocketImpl(this._url);

  bool _isOpen = false;
  final String _url;
  WebSocket _socket;
  OnOpenCallback onOpen;
  OnMessageCallback onMessage;
  OnCloseCallback onClose;

  void connect(
      {Iterable<String> protocols, WebSocketSettings webSocketSettings}) async {
    logger.info('connect $_url, ${webSocketSettings.extraHeaders}, $protocols');
    try {
      var header = webSocketSettings.extraHeaders.cast<String, String>();
      BetterSocket.connentSocket(
        _url,
        httpHeaders: header,
        trustAllHost: webSocketSettings.allowBadCertificate,
      );

      BetterSocket.addListener(
        onOpen: (httpStatus, httpStatusMessage) {
          print(
              'onOpen---httpStatus:$httpStatus httpStatusMessage:$httpStatusMessage');
          _isOpen = true;
          onOpen?.call();
        },
        onMessage: (message) {
          onMessage.call(message);
        },
        onClose: (code, reason, remote) {
          _isOpen = false;
          onClose.call(code as int, 'reason:$reason  remote:$remote');
        },
        onError: (message) {
          _isOpen = false;
          onClose.call(0, 'reason:ERROR  message:$message');
        },
      );

      // if (webSocketSettings.allowBadCertificate) {
      //   /// Allow self-signed certificate, for test only.
      //   _socket = await _connectForBadCertificate(_url, webSocketSettings);
      // } else {
      //   _socket = await WebSocket.connect(_url,
      //       protocols: protocols, headers: webSocketSettings.extraHeaders);
      // }

      // onOpen?.call();
      // _socket.listen((dynamic data) {
      //   onMessage?.call(data);
      // }, onDone: () {
      //   onClose?.call(_socket.closeCode, _socket.closeReason);
      // });
    } catch (e) {
      _isOpen = false;
      onClose?.call(500, e.toString());
    }
  }

  void send(dynamic data) {
    if (_isOpen) {
      // _socket.add(data);
      BetterSocket.sendMsg(data);
      logger.debug('###START#########################################');
      printWrapped('\n\n$data');
      logger.debug('###END#########################################');
    }
  }

  void printWrapped(String text) {
    final RegExp pattern = RegExp('.{1,800}'); // 800 is the size of each chunk
    pattern
        .allMatches(text)
        .forEach((RegExpMatch match) => print(match.group(0)));
  }

  void close() {
    BetterSocket.close();
    // _socket.close();
  }

  bool isConnecting() {
    // return _socket != null && _socket.readyState == WebSocket.connecting;
    return _isOpen;
  }

  /// For test only.
  Future<WebSocket> _connectForBadCertificate(
      String url, WebSocketSettings webSocketSettings) async {
    try {
      Random r = Random();
      String key = base64.encode(List<int>.generate(16, (_) => r.nextInt(255)));
      SecurityContext securityContext = SecurityContext();
      HttpClient client = HttpClient(context: securityContext);

      if (webSocketSettings.userAgent != null) {
        client.userAgent = webSocketSettings.userAgent;
      }

      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        logger.warn('Allow self-signed certificate => $host:$port. ');
        return true;
      };

      Uri parsed_uri = Uri.parse(url);
      Uri uri = parsed_uri.replace(
          scheme: parsed_uri.scheme == 'wss' ? 'https' : 'http');

      HttpClientRequest request =
          await client.getUrl(uri); // form the correct url here
      request.headers.add('Connection', 'Upgrade', preserveHeaderCase: true);
      request.headers.add('Upgrade', 'websocket', preserveHeaderCase: true);
      request.headers.add('Sec-WebSocket-Version', '13',
          preserveHeaderCase: true); // insert the correct version here
      request.headers.add('Sec-WebSocket-Key', key.toLowerCase(),
          preserveHeaderCase: true);
      request.headers
          .add('Sec-WebSocket-Protocol', 'sip', preserveHeaderCase: true);

      webSocketSettings.extraHeaders.forEach((String key, dynamic value) {
        request.headers.add(key, value, preserveHeaderCase: true);
      });

      HttpClientResponse response = await request.close();
      Socket socket = await response.detachSocket();
      WebSocket webSocket = WebSocket.fromUpgradedSocket(
        socket,
        protocol: 'sip',
        serverSide: false,
      );

      return webSocket;
    } catch (e) {
      logger.error('error $e');
      throw e;
    }
  }
}
