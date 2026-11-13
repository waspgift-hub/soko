import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

@JS('svTurnstile')
external JSObject? get _svTurnstile;

@JS('document.createElement')
external JSObject _createElement(JSString tag);

@JS('document.getElementById')
external JSObject? _getElementById(JSString id);

class TurnstileController {
  String? _containerId;
  void _attach(String id) => _containerId = id;
  void _detach() => _containerId = null;

  String get token {
    final id = _containerId;
    final ts = _svTurnstile;
    if (id == null || ts == null) return '';
    try {
      final fn = ts.getProperty<JSFunction?>('getToken'.toJS);
      final v = fn?.callAsFunction(ts, id.toJS);
      if (v == null) return '';
      return (v as JSString).toDart;
    } catch (_) {
      return '';
    }
  }

  void reset() {
    final id = _containerId;
    final ts = _svTurnstile;
    if (id == null || ts == null) return;
    try {
      final fn = ts.getProperty<JSFunction?>('reset'.toJS);
      fn?.callAsFunction(ts, id.toJS);
    } catch (_) {}
  }
}

class TurnstileWidget extends StatefulWidget {
  const TurnstileWidget({
    super.key,
    required this.siteKey,
    required this.action,
    this.controller,
  });

  final String siteKey;
  final String action;
  final TurnstileController? controller;

  @override
  State<TurnstileWidget> createState() => _TurnstileWidgetState();
}

class _TurnstileWidgetState extends State<TurnstileWidget> {
  static int _seq = 0;
  late final String _viewType;
  late final String _containerId;
  bool _registered = false;

  @override
  void initState() {
    super.initState();
    _seq += 1;
    _containerId = 'sv-turnstile-$_seq';
    _viewType = 'sv-turnstile-view-$_seq';
    widget.controller?._attach(_containerId);
    if (kIsWeb && !_registered) {
      _registered = true;
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
        final el = _createElement('div'.toJS);
        el.setProperty('id'.toJS, _containerId.toJS);
        el.setProperty('style'.toJS, 'min-height:65px;display:flex;justify-content:flex-start;'.toJS);
        return el;
      });
      Future<void>.delayed(const Duration(milliseconds: 60), _render);
    }
  }

  Future<void> _render() async {
    if (!kIsWeb) return;
    final ts = _svTurnstile;
    if (ts == null) return;
    try {
      final fn = ts.getProperty<JSFunction?>('render'.toJS);
      fn?.callAsFunction(ts, _containerId.toJS, widget.siteKey.toJS, widget.action.toJS);
    } catch (_) {}
  }

  @override
  void dispose() {
    widget.controller?._detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    return SizedBox(
      height: 72,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
