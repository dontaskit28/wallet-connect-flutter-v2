import 'dart:convert';
import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:eth_sig_util/eth_sig_util.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:hex/hex.dart';
import 'package:http/http.dart' hide Request;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet_connect_v2/wallet_connect_v2.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: HomeView(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with WidgetsBindingObserver {
  static const projectId = '45caf086591c46efb6e9f19b6104d7e8';

  static const _exampleMessage =
      '0x4d7920656d61696c206973206a6f686e40646f652e636f6d202d2031363533333933373535313531';

  final _walletConnectV2Plugin = WalletConnectV2();
  final _walletMetadata = AppMetadata(
      name: 'Flutter Wallet',
      url: 'https://avacus.cc',
      description: 'Flutter Wallet by Avacus',
      icons: ['https://avacus.cc/apple-icon-180x180.png']);
  final List<Session> _sessions = [];

  late String _privateKey;
  late String _address;
  String? _dappTopic;
  String? _tempDappTopic;

  TextEditingController _keyController = TextEditingController();

  bool _isLoading = false;
  bool _isInitiated = false;
  bool _isForeground = true;
  bool _isBackground = false;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
    _walletConnectV2Plugin.onConnectionStatus = (isConnected) async {
      debugPrint('---: CONNECTED: $isConnected');
      if (_isInitiated) {
        if (!isConnected && _isForeground) {
          _walletConnectV2Plugin.connect();
        }
      } else {
        if (isConnected) {
          setState(() {
            _isLoading = false;
            _isInitiated = true;
          });
          _refreshSessions();
        } else {
          setState(() {
            _isLoading = false;
          });
        }
      }
    };
    _walletConnectV2Plugin.onSessionProposal = (proposal) async {
      setState(() {
        _isLoading = false;
      });
      if (proposal.namespaces.length != 1 ||
          !proposal.namespaces.containsKey('eip155') ||
          int.parse(
                  proposal.namespaces['eip155']!.chains.first.split(':')[1]) !=
              5) {
        _showDialog(
            child: const Text('Please choose GOERLI testnet only to do test!'));
        _walletConnectV2Plugin.rejectSession(proposalId: proposal.id);
        return;
      }
      final isApprove = await _showDialog(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Session Proposal'),
          const SizedBox(height: 16),
          Text(proposal.toJson().toString()),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                  child: const Text('Reject')),
              TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Approve')),
            ],
          )
        ],
      ));
      if (isApprove == true) {
        try {
          _walletConnectV2Plugin.approveSession(
            approval: SessionApproval(
              id: proposal.id,
              namespaces: proposal.namespaces.map(
                (key, value) => MapEntry(
                  key,
                  SessionNamespace(
                    accounts: value.chains.map((e) => '$e:$_address').toList(),
                    methods: value.methods,
                    events: value.events,
                    extensions: value.extensions,
                  ),
                ),
              ),
            ),
          );
        } catch (e) {
          _showDialog(child: Text('Approve session error: ${e.toString()}'));
        }
      } else {
        try {
          _walletConnectV2Plugin.rejectSession(proposalId: proposal.id);
        } catch (e) {
          _showDialog(child: Text('Reject session error: ${e.toString()}'));
        }
      }
    };

    _walletConnectV2Plugin.onSessionSettle = (session) async {
      await _refreshSessions();
      if (_tempDappTopic == null) return;
      _dappTopic = session.topic;
      _tempDappTopic = null;
      setState(() {});
      _setDappTopic(_dappTopic!);
    };

    _walletConnectV2Plugin.onSessionRejection = (topic) async {
      await _refreshSessions();
      if (_tempDappTopic == topic) {
        _tempDappTopic = null;
        setState(() {});
      }
    };

    _walletConnectV2Plugin.onSessionResponse = (response) async {
      _showDialog(
          child: Text(
              'Message: $_exampleMessage\n\n${response.results is String ? 'Signature' : 'Error'}: ${response.results}'));
    };

    _walletConnectV2Plugin.onSessionUpdate = (_) {
      _refreshSessions();
    };

    _walletConnectV2Plugin.onSessionDelete = (_) {
      _refreshSessions();
    };

    _walletConnectV2Plugin.onEventError = (code, message) {
      _showDialog(child: Text(message));
    };

    _walletConnectV2Plugin.onSessionRequest = (request) async {
      final isApprove = await _showDialog(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Session Request'),
          const SizedBox(height: 16),
          Text(request.toJson().toString()),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                  child: const Text('Reject')),
              TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Approve')),
            ],
          )
        ],
      ));
      if (isApprove) {
        switch (request.method) {
          case 'eth_sendTransaction':
          case 'eth_signTransaction':
            try {
              final object = request.params.first as Map;
              final gasLimit = object['gasLimit'] != null
                  ? BigInt.tryParse(object['gasLimit'])
                  : null;
              final gasPrice = object['gasPrice'] != null
                  ? EtherAmount.fromUnitAndValue(
                      EtherUnit.wei, object['gasPrice'])
                  : null;
              final value = object['value'] != null
                  ? EtherAmount.fromUnitAndValue(EtherUnit.wei, object['value'])
                  : null;
              final from = object['from'] != null
                  ? EthereumAddress.fromHex(object['from'])
                  : null;
              final to = object['to'] != null
                  ? EthereumAddress.fromHex(object['to'])
                  : null;
              final data =
                  object['data'] != null ? hexToBytes(object['data']) : null;
              final tx = Transaction(
                from: from,
                data: data,
                value: value,
                maxGas: gasLimit?.toInt(),
                to: to,
                gasPrice: gasPrice,
              );
              final client =
                  Web3Client('https://rpc.ankr.com/eth_goerli', Client());
              final signature = await client.signTransaction(
                  EthPrivateKey.fromHex(_privateKey), tx);
              await _walletConnectV2Plugin.approveRequest(
                  topic: request.topic,
                  requestId: request.id,
                  result: bytesToHex(signature, include0x: true));
            } catch (e) {
              _showDialog(child: Text('Sign error: ${e.toString()}'));
            }
            break;
          case 'personal_sign':
          case 'eth_sign':
            try {
              final message =
                  request.params.firstWhere((element) => element != _address);
              final signature = EthSigUtil.signPersonalMessage(
                  message: hexToBytes(message), privateKey: _privateKey);
              await _walletConnectV2Plugin.approveRequest(
                  topic: request.topic,
                  requestId: request.id,
                  result: signature);
            } catch (e) {
              _showDialog(child: Text('Approve error: ${e.toString()}'));
            }
            break;
          case 'eth_signTypedData':
            try {
              final message =
                  request.params.firstWhere((element) => element != _address);
              final jsonData = message is Map ? jsonEncode(message) : message;
              final signature = EthSigUtil.signTypedData(
                  jsonData: jsonData.toString(),
                  privateKey: _privateKey,
                  version: TypedDataVersion.V4);
              await _walletConnectV2Plugin.approveRequest(
                  topic: request.topic,
                  requestId: request.id,
                  result: signature);
            } catch (e) {
              _showDialog(
                  child: Text('Approve request error: ${e.toString()}'));
            }
            break;
          default:
            _showDialog(child: Text('Unhandled method ${request.method}'));
            break;
        }
      } else {
        try {
          await _walletConnectV2Plugin.rejectRequest(
              topic: request.topic, requestId: request.id);
        } catch (e) {
          _showDialog(child: Text('Reject request error: ${e.toString()}'));
        }
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Wallet Connect V2'),
      ),
      body: SafeArea(
        child: Center(
          child: _isLoading
              ? const CupertinoActivityIndicator()
              : _isInitiated
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Sessions:'),
                          Expanded(
                            child: _sessions.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No sessions\n\nPair wallet connect uri and approve to have session',
                                      textAlign: TextAlign.center,
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    itemBuilder: (_, index) {
                                      final session = _sessions[index];
                                      return Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            width: 1,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        child: ListTile(
                                          title: Text(session.peer.name),
                                          subtitle: Text(session.peer.url),
                                          trailing: TextButton(
                                            onPressed: () async {
                                              await _walletConnectV2Plugin
                                                  .disconnectSession(
                                                      topic: session.topic);
                                              _refreshSessions();
                                            },
                                            child: const Text('Disconnect'),
                                          ),
                                        ),
                                      );
                                    },
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 16),
                                    itemCount: _sessions.length,
                                  ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton(
                                onPressed: () async {
                                  var response =
                                      await FlutterBarcodeScanner.scanBarcode(
                                    '#ff6666',
                                    'Cancel',
                                    true,
                                    ScanMode.QR,
                                  );
                                  try {
                                    setState(() {
                                      _isLoading = true;
                                    });
                                    final uri = response;

                                    if (uri.trim().isEmpty) {
                                      _showDialog(
                                        child: const Text(
                                          'Please paste the WalletConnect V2 URI then do Pair',
                                        ),
                                      );
                                      return;
                                    }

                                    await _walletConnectV2Plugin.pair(uri: uri);
                                  } catch (e) {
                                    _showDialog(
                                        child: Text(
                                            'Pair error: ${e.toString()}'));
                                  } finally {
                                    setState(() {
                                      _isLoading = false;
                                    });
                                  }
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    'Scan QR Code',
                                    style: TextStyle(
                                      fontSize: 24,
                                    ),
                                  ),
                                ),
                              )
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: MediaQuery.of(context).size.width * 0.7,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: TextField(
                                controller: _keyController,
                                decoration: const InputDecoration(
                                  hintText: "Enter Private Key",
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.all(10),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                Clipboard.getData('text/plain').then((value) {
                                  _keyController.text = value!.text!;
                                });
                              },
                              icon: const Icon(Icons.paste),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () async {
                            setState(() {
                              _isLoading = true;
                            });
                            await _initWallet();

                            await _walletConnectV2Plugin.init(
                              projectId: projectId,
                              appMetadata: _walletMetadata,
                            );
                            await _walletConnectV2Plugin.connect();
                            setState(() {
                              _isLoading = false;
                              _isInitiated = true;
                            });
                          },
                          child: const Text('Submit'),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  Future _refreshSessions() async {
    try {
      final sessions = await _walletConnectV2Plugin.getActivatedSessions();
      if (sessions
          .where((element) => element.topic == _dappTopic)
          .toList()
          .isEmpty) {
        _setDappTopic(_dappTopic = null);
      }
      _sessions.clear();
      _sessions.addAll(sessions);
      setState(() {});
    } catch (e) {
      _showDialog(
        child: Text('Refresh sessions error: ${e.toString()}'),
      );
    }
  }

  Future _showDialog({required Widget child}) {
    return showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          backgroundColor: Colors.transparent,
          child: Card(
            clipBehavior: Clip.antiAlias,
            color: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        );
      },
    );
  }

  Future _initWallet() async {
    _privateKey = _keyController.text;
    final private = EthPrivateKey.fromHex(_privateKey);
    _address = (await private.extractAddress()).hexEip55;
    _refreshSessions();
  }

  Future _setDappTopic(String? topic) async {
    final sp = await SharedPreferences.getInstance();
    if (topic != null) {
      return sp.setString('dapp_topic', topic);
    }
    return sp.remove('dapp_topic');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        _isBackground = false;
        _isForeground = true;
        debugPrint('---: DO CONNECT');
        if (_isInitiated) {
          _walletConnectV2Plugin.connect();
        }
        break;
      case AppLifecycleState.inactive:
        _isForeground = false;
        if (!_isBackground) {
          debugPrint('---: DO DISCONNECT');
          if (_isInitiated) {
            _walletConnectV2Plugin.disconnect();
          }
        }
        break;
      case AppLifecycleState.paused:
        _isForeground = false;
        _isBackground = true;
        break;
      case AppLifecycleState.detached:
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _walletConnectV2Plugin.dispose();
    super.dispose();
  }
}
