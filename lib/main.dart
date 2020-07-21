import 'dart:convert';
import 'dart:ui';

import 'package:dash_chat/dash_chat.dart';
import 'package:flushbar/flushbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:http_client/browser.dart' as http;
import 'package:web_socket_channel/html.dart';

void main() {
  runApp(Application());
}

class Application extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        initialRoute: "/username",
        routes: {
          "/username": (context) => UserNameWidget(),
          "/dashboard": (context) => DashBoardWidget()
        },
      );
}

class UserNameWidget extends StatefulWidget {
  String username;
  final client = http.BrowserClient();

  @override
  _UserNameWidgetState createState() => _UserNameWidgetState();
}

class _UserNameWidgetState extends State<UserNameWidget> {
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Container(
                        height: 100,
                        width: 200,
                        child: TextField(
                          decoration: InputDecoration(labelText: 'Username'),
                          onChanged: (value) => widget.username = value,
                        ),
                      ),
                    ),
                    MaterialButton(
                        child: Text('Go!'),
                        onPressed: () => widget.client
                                .send(http.Request(
                                    'POST', 'https://lavash.cfapps.io/user/login',
                                    json: {'username': widget.username}))
                                .then((value) {
                              SchedulerBinding.instance
                                  .addPostFrameCallback((timeStamp) {
                                Navigator.pushReplacementNamed(
                                    context, '/dashboard',
                                    arguments:
                                        jsonDecode(value.body)['message']);
                              });
                            }))
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class DashBoardWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Row(
          children: <Widget>[
            Expanded(
                child:
                    PresenceWidget(ModalRoute.of(context).settings.arguments)),
            SizedBox(
              width: .5,
              child: Container(
                color: Colors.grey,
              ),
            ),
            Expanded(
                flex: 4,
                child: ChatWidget(ModalRoute.of(context).settings.arguments))
          ],
        ),
      );
}

class ChatWidget extends StatefulWidget {
  String username = '';

  ChatWidget(this.username);

  @override
  _ChatWidgetState createState() => _ChatWidgetState();
}

class _ChatWidgetState extends State<ChatWidget> {
  final messageClient =
      HtmlWebSocketChannel.connect(Uri.parse('wss://lavash.cfapps.io:4443/messages'));

  final typingClient =
      HtmlWebSocketChannel.connect(Uri.parse('wss://lavash.cfapps.io:4443/typing'));

  final messages = [];
  final typingList = [];

  @override
  void initState() {
    if (widget.username == null) {
      SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
        Navigator.pushReplacementNamed(
          context,
          '/username',
        );
      });
    }

    messageClient.stream
        .map((message) => jsonDecode(message))
        .listen((message) {
      if (mounted) {
        setState(() => messages.add(message));
      }
    });

    typingClient.stream.map((message) => jsonDecode(message)).listen((message) {
      typingList.removeWhere((element) =>
          (element['id'] == message['id'] && message['typing'] == false) ||
          element['id'] == message['id']);
      if (message['username'] != widget.username && message['typing'] == true) {
        if (mounted) {
          setState(() => typingList.add(message));
        }

        Flushbar(
          flushbarPosition: FlushbarPosition.TOP,
          title: 'typing...',
          message: typingList.map((e) => e['username']).join(', '),
        )..show(context);
      }
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      child: DashChat(
          inputContainerStyle:
              BoxDecoration(color: Theme.of(context).primaryColor),
//        onTextChange: (message) => typingClient.sink
//            .add('{"username" : "${widget.username}","typing" : "true"}'),
          sendOnEnter: true,
          messages: messages
              .map((e) => ChatMessage(
                  createdAt:
                      DateTime.fromMillisecondsSinceEpoch(e['timestamp']),
                  text: e['text'],
                  user: ChatUser(uid: e['from'], name: e['from'])))
              .toList(),
          user: ChatUser(uid: widget.username, name: widget.username),
          onSend: (message) => messageClient.sink.add(
              '{"text" : "${message.text}","from" : "${message.user.name}"}')),
    );
  }
}

class PresenceWidget extends StatefulWidget {
  String username = '';

  PresenceWidget(this.username);

  @override
  _PresenceWidgetState createState() => _PresenceWidgetState();
}

class _PresenceWidgetState extends State<PresenceWidget> {
  final client =
      HtmlWebSocketChannel.connect(Uri.parse('wss://lavash.cfapps.io:4443/presence'));

  final list = <dynamic>{};

  @override
  void initState() {
    super.initState();

    if (widget.username != null) {
      client.sink.add('{"username" : "${widget.username}"}');
    } else {
      SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
        Navigator.pushReplacementNamed(context, '/username');
      });
    }

    client.stream.map((message) => jsonDecode(message)).listen((message) {
      list.removeWhere((element) =>
          (element['id'] == message['id'] && message['present'] == false) ||
          element['id'] == message['id']);
      if (message['username'] != widget.username &&
          message['present'] == true) {
        if (mounted) {
          setState(() => list.add(message));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
        children: ListTile.divideTiles(
            context: context,
            tiles: list.map((e) => ListTile(
                  contentPadding: EdgeInsets.all(10),
                  title: Text(
                    e['username'] == widget.username ? "Me!" : e['username'],
                    textAlign: TextAlign.start,
                    style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
                  ),
                  leading: Icon(
                    Icons.brightness_1,
                    color: Colors.greenAccent,
                    size: 15,
                  ),
                ))).toList(),
      );
}
