import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:usb_serial/transaction.dart';
import 'package:usb_serial/usb_serial.dart';

import 'package:http/http.dart' as http;

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Timer _timer = Timer(Duration(milliseconds: 1000), () {});
  UsbPort? _port;
  String _status = "Idle";
  List<Widget> _ports = [];
  List<Widget> _serialData = [];

  List<int> iDataList = [0, 0, 0, 0, 0, 0, 0, 0];

  Uint8List totalEvent = Uint8List(64);

  int cmdIndex = 0;

  StreamSubscription<String>? _subscription;
  Transaction<String>? _transaction;
  UsbDevice? _device;

  TextEditingController _textController = TextEditingController();

  static String uint8ToHex(Uint8List byteArr) {
    if (byteArr == null || byteArr.length == 0) {
      return "";
    }
    Uint8List result = Uint8List(byteArr.length << 1);
    var hexTable = [
      '0',
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      'A',
      'B',
      'C',
      'D',
      'E',
      'F'
    ]; //16进制字符表
    for (var i = 0; i < byteArr.length; i++) {
      var bit = byteArr[i]; //取传入的byteArr的每一位
      var index = bit >> 4 & 15; //右移4位,取剩下四位
      var i2 = i << 1; //byteArr的每一位对应结果的两位,所以对于结果的操作位数要乘2
      result[i2] = hexTable[index].codeUnitAt(0); //左边的值取字符表,转为Unicode放进resut数组
      index = bit & 15; //取右边四位
      result[i2 + 1] =
          hexTable[index].codeUnitAt(0); //右边的值取字符表,转为Unicode放进resut数组
    }
    return String.fromCharCodes(result); //Unicode转回为对应字符,生成字符串返回
  }

  Uint8List crc16(Uint8List bytes) {
    // CCITT
    const POLYNOMIAL = 0x1021;
    // XMODEM
    const INIT_VALUE = 0x0000;

    final bitRange = Iterable.generate(8);

    var crc = INIT_VALUE;
    for (var byte in bytes) {
      crc ^= (byte << 8);
      for (var i in bitRange) {
        crc = (crc & 0x8000) != 0 ? (crc << 1) ^ POLYNOMIAL : crc << 1;
      }
    }
    // FIXME setInt16 or setUint16
    var byteData = ByteData(2)..setInt16(0, crc, Endian.little);
    return byteData.buffer.asUint8List();
  }

  Future<bool> _connectTo(device) async {
    _serialData.clear();

    if (_subscription != null) {
      _subscription!.cancel();
      _subscription = null;
    }

    if (_transaction != null) {
      _transaction!.dispose();
      _transaction = null;
    }

    if (_port != null) {
      _port!.close();
      _port = null;
    }

    if (device == null) {
      _device = null;
      setState(() {
        _status = "Disconnected";
      });

      _timer.cancel();

      return true;
    }

    // UsbPort port;
    // _port = await device.create();

    // bool openResult = await _port!.open();
    // if (!openResult) {
    //   print("Failed to open");
    //   return true;
    // }

    // await _port!.setDTR(true);
    // await _port!.setRTS(true);

    // await _port!.setPortParameters(
    //     9600, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

    // // print first result and close port.
    // await _port!.inputStream!.listen((Uint8List event) {
    //   print(event);
    //   // port.close();
    // });

    _port = await device.create();
    if (await (_port!.open()) != true) {
      setState(() {
        _status = "Failed to open port";
      });
      return false;
    }
    _device = device;

    await _port!.setDTR(true);
    await _port!.setRTS(true);

    _port!.setPortParameters(
        9600, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

    iDataList[0] = 0;
    iDataList[1] = 0;
    iDataList[2] = 0;
    iDataList[3] = 0;
    iDataList[4] = 0;
    iDataList[5] = 0;
    iDataList[6] = 0;
    iDataList[7] = 0;

    _port!.inputStream!.listen((Uint8List event) {
      // print(event.length);

      setState(() {
        // String fullString = String.fromCharCodes(event);

        // for (int i = 0; i < event.length; i++) {
        //   totalEvent.add(event[i]);
        // }
        // crc16()

        String fullString = uint8ToHex(event);

        // [0xcc, 3, 0, 3, 0, 3, 0xe5, 0xd6], // radiation
        // [0xc8, 3, 0, 0, 0, 2, 0xd5, 0x92], // wind
        // [0x66, 3, 0, 0, 0, 8, 0x4c, 0x1b], // temperature

        // [0xc9, 3, 0, 0, 0, 2, 0xd4, 0x43], // rainfall

        // [0xdc, 3, 0, 3, 0, 3, 0xe7, 0x46], // raditaion - outdoor
        // [0xd8, 3, 0, 0, 0, 2, 0xD7, 0x02], // wind - outdoor
        // [0x76, 3, 0, 0, 0, 8, 0x4E, 0x8b], // temperature

        // [0xd9, 3, 0, 0, 0, 2, 0xd6, 0xd3], // rainfall - outdoor

        if (event[0] == 0xcc) iDataList[0] += 1;
        if (event[0] == 0xc8) iDataList[1] += 1;
        if (event[0] == 0x66) iDataList[2] += 1;
        if (event[0] == 0xc9) iDataList[3] += 1;
        if (event[0] == 0xdc) iDataList[4] += 1;
        if (event[0] == 0xd8) iDataList[5] += 1;
        if (event[0] == 0x76) iDataList[6] += 1;
        if (event[0] == 0xd9) iDataList[7] += 1;

        // if (event[0] == 0xc9) {
        //   _serialData.add(Text("RAINFALL=" +
        //       ((event[6] / 100).toString()) +
        //       "mm")); // fullString));

        //   if (_serialData.length > 10) {
        //     _serialData.removeAt(0);
        //   }
        //   print(Text("RAINFALL=" + ((event[6] / 100).toString()) + "mm"));
        // }

        // if (event[0] == 0xd9) {
        //   _serialData.add(Text("OUTDOOR RAINFALL=" +
        //       ((event[6] / 100).toString()) +
        //       "mm")); // fullString));

        //   if (_serialData.length > 10) {
        //     _serialData.removeAt(0);
        //   }
        //   print(
        //       Text("OUTDOOR RAINFALL=" + ((event[6] / 100).toString()) + "mm"));
        // }

        print(fullString);
        _serialData.add(Text(fullString)); // fullString));

        // _serialData.add(Text(iDataList[0].toString() +
        //     ',' +
        //     iDataList[1].toString() +
        //     ',' +
        //     iDataList[2].toString() +
        //     ',' +
        //     iDataList[3].toString() +
        //     ',' +
        //     iDataList[4].toString() +
        //     ',' +
        //     iDataList[5].toString() +
        //     ',' +
        //     iDataList[6].toString() +
        //     ',' +
        //     iDataList[7].toString())); // fullString));

        if (_serialData.length > 10) {
          _serialData.removeAt(0);
        }
      });
    });

    void _callAPI() async {
      var url = Uri.parse(
        'https://raw.githubusercontent.com/dev-yakuza/users/master/api.json',
      );
      var response = await http.get(url);
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      // url = Uri.parse('https://reqbin.com/sample/post/json');
      // response = await http.post(url, body: {
      //   'key': 'value',
      // });
      // print('Response status: ${response.statusCode}');
      // print('Response body: ${response.body}');
    }

    _transaction = Transaction.stringTerminated(
        _port!.inputStream as Stream<Uint8List>,
        Uint8List.fromList([0xd4, 0x56]));

    _subscription = _transaction!.stream.listen((String line) {
      setState(() {
        _serialData.add(Text(line));
        if (_serialData.length > 10) {
          _serialData.removeAt(0);
        }
      });
    });

    setState(() {
      _status = "Connected";
    });

    _timer = Timer.periodic(Duration(milliseconds: 1000), (timer) {
      // print('#sendTimer');

      // List<int> data = [204, 3, 0, 3, 0, 2, 0x24, 0x16];
      // Uint8List bytes = Uint8List.fromList(data);
      List<List<int>> data = [
        // [0xcc, 3, 0, 3, 0, 2, 0x24, 0x16], // radiation

        [0xcc, 3, 0, 3, 0, 3, 0xe5, 0xd6], // radiation
        [0xc8, 3, 0, 0, 0, 2, 0xd5, 0x92], // wind
        [0x66, 3, 0, 0, 0, 8, 0x4c, 0x1b], // temperature

        [0xc9, 3, 0, 0, 0, 2, 0xd4, 0x43], // rainfall

        [0xdc, 3, 0, 3, 0, 3, 0xe7, 0x46], // raditaion - outdoor
        [0xd8, 3, 0, 0, 0, 2, 0xD7, 0x02], // wind - outdoor
        [0x76, 3, 0, 0, 0, 8, 0x4E, 0x8b], // temperature

        [0xd9, 3, 0, 0, 0, 2, 0xd6, 0xd3], // rainfall - outdoor
      ];

      cmdIndex += 1;
      if (data.length <= cmdIndex) cmdIndex = 0; // 0, 1, 2

      // print('send=' + cmdIndex.toString());
      Uint8List bytes = Uint8List.fromList(data[cmdIndex]);

      _port!.write(bytes);

      setState(() {});
    });

    return true;
  }

  void _getPorts() async {
    _ports = [];
    List<UsbDevice> devices = await UsbSerial.listDevices();
    if (!devices.contains(_device)) {
      _connectTo(null);
    }

    // print('devices');
    // print(devices);

    devices.forEach((device) {
      _ports.add(ListTile(
          leading: Icon(Icons.usb),
          title: Text(device.productName!),
          // zw block! subtitle: Text(device.manufacturerName!),
          trailing: ElevatedButton(
            child: Text(_device == device ? "Disconnect" : "Connect"),
            onPressed: () {
              _connectTo(_device == device ? null : device).then((res) {
                _getPorts();
              });
            },
          )));
    });

    setState(() {
      print(_ports);
    });
  }

  @override
  void initState() {
    super.initState();

    UsbSerial.usbEventStream!.listen((UsbEvent event) {
      _getPorts();
    });

    _getPorts();
  }

  @override
  void dispose() {
    _timer.cancel();

    super.dispose();
    _connectTo(null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          appBar: AppBar(
            title: const Text('USB_SERIAL'),
          ),
          body: Center(
              child: Column(children: <Widget>[
            Text(
                _ports.length > 0
                    ? "Available Serial Ports"
                    : "No serial devices available",
                style: Theme.of(context).textTheme.headline6),
            ..._ports,
            Text('Status: $_status\n'),
            Text('info: ${_port.toString()}\n'),
            ListTile(
              title: TextField(
                controller: _textController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Text To Send',
                ),
              ),
              trailing: ElevatedButton(
                child: Text("Send"),
                onPressed:
                    // _port == null
                    // ? null
                    // : () async

                    () async {
                  var url = Uri.parse(
                    'https://raw.githubusercontent.com/dev-yakuza/users/master/api.json',
                  );
                  // var response = http.get(url);
                  // print(response);

                  http.Response response = await http.get(url);
                  try {
                    if (response.statusCode == 200) {
                      String data = response.body;
                      var decodedData = jsonDecode(data);
                      print(decodedData);

                      // return decodedData;
                    } else {
                      // return 'failed';
                      print('failed#1');
                    }
                  } catch (e) {
                    // return 'failed';
                    print('failed#2');
                  }

                  // print('Response status: ${response}');
                  // print('Response body: ${response.body}');

                  // if (_port == null) {
                  //   return;
                  // }
                  // // String data = _textController.text + "\r\n";
                  // // await _port!.write(Uint8List.fromList(data.codeUnits));

                  // // const data = new Uint8Array(
                  // //     [204, 3, 0, 3, 0, 2, 0x24, 0x16]);
                  // // print('send', data);
                  // List<List<int>> data = [
                  //   [0xcc, 3, 0, 0, 0, 5, 0x94, 0xd4], // radiation
                  //   [0xc8, 3, 0, 0, 0, 2, 0xd5, 0x92], // wind
                  //   [0x66, 3, 0, 0, 0, 8, 0x4c, 0x1b], // temperature
                  // ];

                  // cmdIndex += 1;
                  // if (3 <= cmdIndex) cmdIndex = 0; // 0, 1, 2

                  // // print('send=' + cmdIndex.toString());

                  // Uint8List bytes = Uint8List.fromList(data[cmdIndex]);
                  // await _port!.write(bytes);
                  // _textController.text = "";
                },
              ),
            ),
            Text("Result Data", style: Theme.of(context).textTheme.headline6),
            ..._serialData,
          ])),
        ));
  }
}
