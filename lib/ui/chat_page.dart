import 'package:flutter/material.dart';

import '../assistant/assistant.dart';
import '../voice/voice_service.dart';
import 'glow_background.dart';
import 'theme.dart';

class _Msg {
  const _Msg(this.text, {required this.fromUser});
  final String text;
  final bool fromUser;
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.assistant, required this.voice});

  final Assistant assistant;
  final VoiceService voice;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const _examples = [
    'Напомни завтра в 10 утра позвонить Ивану',
    'Добавь встречу с командой завтра в 15:00',
    'Что у меня сегодня?',
    'Найди задачу про презентацию',
  ];

  final _msgs = <_Msg>[];
  final _ctrl = TextEditingController();
  String _headline = 'Чем помочь?';
  String _reply =
      'Скажите или напишите, например: «Напомни завтра в 10 утра позвонить Ивану»';
  bool _listening = false;
  bool _speak = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.voice.onListening = (v) {
      if (mounted) setState(() => _listening = v);
    };
  }

  @override
  void dispose() {
    _ctrl.dispose();
    widget.voice.stopSpeaking();
    super.dispose();
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;
    _ctrl.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _msgs.add(_Msg(text, fromUser: true));
      _headline = text;
      _busy = true;
    });

    AssistantReply reply;
    try {
      reply = await widget.assistant.handle(text);
    } catch (_) {
      reply = const AssistantReply('Что-то пошло не так. Попробуйте ещё раз.');
    }
    if (!mounted) return;
    setState(() {
      _msgs.add(_Msg(reply.text, fromUser: false));
      _reply = reply.text;
      _busy = false;
    });
    if (_speak) widget.voice.speak(reply.text);
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
    setState(() => _headline = 'Слушаю…');
    await widget.voice.listen((words, isFinal) {
      if (!mounted) return;
      if (isFinal) {
        if (words.trim().isNotEmpty) {
          _send(words);
        } else {
          setState(() => _headline = 'Не расслышал. Повторите');
        }
      } else if (words.isNotEmpty) {
        setState(() => _headline = words);
      }
    });
  }

  void _showHistory() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        child: _msgs.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Text('История пока пуста',
                    style: TextStyle(color: Colors.white54, fontSize: 18)),
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
                          color: m.fromUser ? kAccent : Colors.white70,
                          fontSize: 16,
                          fontWeight:
                              m.fromUser ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _topBar() => Row(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Icon(Icons.auto_awesome, color: Colors.white),
          ),
          Expanded(
            child: Center(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Ассистент',
                        style: TextStyle(
                            color: kAccent,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        setState(() => _speak = !_speak);
                        if (!_speak) widget.voice.stopSpeaking();
                      },
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: kAccent,
                        child: Icon(
                          _speak ? Icons.volume_up : Icons.volume_off,
                          color: Colors.black,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'История',
            onPressed: _showHistory,
            icon: const Icon(Icons.history, color: Colors.white, size: 28),
          ),
        ],
      );

  Widget _micButton(double d) => GestureDetector(
        onTap: _toggleMic,
        child: AnimatedScale(
          scale: _listening ? 1.1 : 1,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: d,
            height: d,
            decoration: BoxDecoration(
              color: kAccent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: kAccent.withValues(alpha: _listening ? 0.55 : 0.25),
                  blurRadius: _listening ? 60 : 30,
                  spreadRadius: _listening ? 12 : 2,
                ),
              ],
            ),
            child: Icon(
              _listening ? Icons.stop_rounded : Icons.mic,
              color: Colors.black,
              size: d * 0.5,
            ),
          ),
        ),
      );

  Widget _inputPill() => Container(
        padding: const EdgeInsets.only(left: 22, right: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(32),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                cursorColor: kAccent,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Или напишите…',
                  hintStyle: TextStyle(color: Colors.white54),
                ),
              ),
            ),
            IconButton(
              onPressed: _busy ? null : () => _send(_ctrl.text),
              icon: const Icon(Icons.arrow_upward_rounded,
                  color: kAccent, size: 28),
            ),
          ],
        ),
      );

  Widget _chips() => SizedBox(
        height: 42,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _examples.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => _send(_examples[i]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(_examples[i],
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final keyboard = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: GlowBackground(active: _listening)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _topBar(),
                  Expanded(
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          _headline,
                          key: ValueKey(_headline),
                          textAlign: TextAlign.center,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: _headline.length > 40 ? 30 : 46,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_reply.isNotEmpty)
                    Container(
                      width: double.infinity,
                      constraints: BoxConstraints(
                          maxHeight: size.height * (keyboard ? 0.16 : 0.26)),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: SingleChildScrollView(
                        child: Text(_reply,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                height: 1.35)),
                      ),
                    ),
                  const SizedBox(height: 16),
                  _micButton(keyboard ? 60 : 92),
                  const SizedBox(height: 16),
                  if (_msgs.isEmpty && !keyboard) ...[
                    _chips(),
                    const SizedBox(height: 12),
                  ],
                  _inputPill(),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
