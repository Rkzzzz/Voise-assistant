import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../assistant/assistant.dart';
import '../models/entry.dart';
import '../voice/voice_service.dart';
import 'format.dart';
import 'theme.dart';

class _Msg {
  const _Msg(this.text, {required this.fromUser});
  final String text;
  final bool fromUser;
}

/// Главный экран: большой микрофон, «таблетка» с ответом и осьминог.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.assistant, required this.voice});

  final Assistant assistant;
  final VoiceService voice;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const _hint =
      'Нажмите на микрофон и скажите, например: «Напомни завтра в 10 утра позвонить Ивану»';
  static const _mascotAspect = 406 / 180;

  final _msgs = <_Msg>[];
  final _ctrl = TextEditingController();
  String _reply = _hint;
  String _lastUser = '';
  String _partial = '';
  bool _listening = false;
  bool _busy = false;
  bool _typing = false;
  Entry? _next;
  Timer? _timer;

  Assistant get _a => widget.assistant;

  @override
  void initState() {
    super.initState();
    widget.voice.onListening = (v) {
      if (mounted) setState(() => _listening = v);
    };
    _a.addListener(_refreshNext);
    _a.appSettings.addListener(_onSettings);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshNext());
    _refreshNext();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _a.removeListener(_refreshNext);
    _a.appSettings.removeListener(_onSettings);
    _ctrl.dispose();
    widget.voice.stopSpeaking();
    super.dispose();
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshNext() async {
    final e = await _a.nextUpcoming();
    if (mounted) setState(() => _next = e);
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;
    _ctrl.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _msgs.add(_Msg(text, fromUser: true));
      _lastUser = text;
      _partial = '';
      _typing = false;
      _busy = true;
    });

    AssistantReply reply;
    try {
      reply = await _a.handle(text);
    } catch (e, st) {
      debugPrint('assistant error: $e\n$st');
      reply = const AssistantReply('Что-то пошло не так. Попробуйте ещё раз.');
    }
    if (!mounted) return;
    setState(() {
      _msgs.add(_Msg(reply.text, fromUser: false));
      _reply = reply.text;
      _busy = false;
    });
    if (_a.appSettings.speak) widget.voice.speak(reply.text);
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await widget.voice.stopListening();
      return;
    }
    await widget.voice.stopSpeaking();
    final ok = await widget.voice.init();
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Нет доступа к микрофону или распознаванию речи'),
      ));
      return;
    }
    setState(() {
      _partial = '';
      _typing = false;
    });
    await widget.voice.listen((words, isFinal) {
      if (!mounted) return;
      if (isFinal) {
        if (words.trim().isNotEmpty) {
          _send(words);
        } else {
          setState(() => _reply = 'Не расслышал. Повторите, пожалуйста.');
        }
      } else if (words.isNotEmpty) {
        setState(() => _partial = words);
      }
    });
  }

  void _showHistory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        child: _msgs.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(32),
                child:
                    Text('История пока пуста', style: TextStyle(fontSize: 18)),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: _msgs.length,
                itemBuilder: (_, i) {
                  final m = _msgs[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Align(
                      alignment: m.fromUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Text(
                        m.text,
                        textAlign:
                            m.fromUser ? TextAlign.right : TextAlign.left,
                        style: TextStyle(
                          color:
                              fg(ctx).withValues(alpha: m.fromUser ? 1 : 0.8),
                          fontSize: 16,
                          fontWeight:
                              m.fromUser ? FontWeight.w800 : FontWeight.w400,
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  // ---------- Части экрана ----------

  Widget _topBar(Pal p) {
    final s = _a.appSettings;
    final e = _next;
    return Row(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: widget.voice.speaking,
          builder: (_, speaking, __) => IconButton(
            tooltip: speaking ? 'Остановить речь' : 'Озвучка ответов',
            onPressed: () {
              if (speaking) {
                widget.voice.stopSpeaking();
              } else {
                s.change(speak: !s.speak);
              }
            },
            icon: Icon(
              speaking
                  ? Icons.stop_circle
                  : (s.speak ? Icons.volume_up : Icons.volume_off),
              size: 28,
              color: speaking ? const Color(0xFFE5645F) : p.text,
            ),
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Text(s.assistantName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: kDisplayFont,
                      color: p.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
              if (e != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('${e.title} — ${untilText(e, _a.now)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.text.withValues(alpha: 0.7), fontSize: 12)),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'История',
          onPressed: _showHistory,
          icon: Icon(Icons.history, size: 28, color: p.text),
        ),
      ],
    );
  }

  Widget _mic(Pal p, double d) => GestureDetector(
        onTap: _toggleMic,
        child: AnimatedScale(
          scale: _listening ? 1.07 : 1,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: d,
            height: d,
            decoration: BoxDecoration(
              color: p.circle,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: p.glow.withValues(alpha: _listening ? 0.6 : 0.35),
                  blurRadius: _listening ? 70 : 40,
                  spreadRadius: _listening ? 10 : 2,
                ),
              ],
            ),
            child: Icon(
              _listening ? Icons.stop_rounded : Icons.mic,
              color: p.onCircle,
              size: d * 0.5,
            ),
          ),
        ),
      );

  Widget _pillBody(Pal p) {
    if (_typing) {
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              cursorColor: p.text,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
              style: TextStyle(color: p.text, fontSize: 17),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Напишите запрос…',
                hintStyle: TextStyle(color: p.text.withValues(alpha: 0.5)),
              ),
            ),
          ),
          IconButton(
            onPressed: _busy ? null : () => _send(_ctrl.text),
            icon: Icon(Icons.arrow_upward_rounded, color: p.text, size: 28),
          ),
        ],
      );
    }

    final String main;
    if (_listening) {
      main = _partial.isEmpty ? 'Слушаю…' : _partial;
    } else if (_busy) {
      main = 'Думаю…';
    } else {
      main = _reply;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_lastUser.isNotEmpty && !_listening && !_busy)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('«$_lastUser»',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.text.withValues(alpha: 0.6),
                            fontSize: 13)),
                  ),
                Text(main,
                    style:
                        TextStyle(color: p.text, fontSize: 16, height: 1.35)),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Написать',
          onPressed: () => setState(() => _typing = true),
          icon: Icon(Icons.keyboard_alt_outlined,
              color: p.text.withValues(alpha: 0.8)),
        ),
      ],
    );
  }

  Widget _mascotAndPill(Pal p, double maxPillH) {
    final w = MediaQuery.of(context).size.width * 0.62;
    final h = w / _mascotAspect;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -4,
          top: -(h - 30),
          child: IgnorePointer(
            child: Image.asset(
              'assets/mascot.png',
              width: w,
              errorBuilder: (_, __, ___) =>
                  const Text('🐙', style: TextStyle(fontSize: 72)),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: 96, maxHeight: maxPillH),
          padding: const EdgeInsets.fromLTRB(24, 12, 8, 12),
          decoration: BoxDecoration(
            color: p.pill,
            borderRadius: BorderRadius.circular(36),
          ),
          child: _pillBody(p),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              _topBar(p),
              Expanded(
                child: LayoutBuilder(
                  builder: (_, c) {
                    final d = math.max(
                        48.0,
                        math.min(240.0,
                            math.min(c.maxWidth * 0.5, c.maxHeight - 20)));
                    return Center(child: _mic(p, d));
                  },
                ),
              ),
              _mascotAndPill(p, size.height * 0.3),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
