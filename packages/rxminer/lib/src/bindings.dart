import 'dart:ffi';

import 'package:ffi/ffi.dart';

@Native<Pointer<Utf8> Function()>(symbol: 'rxminer_device')
external Pointer<Utf8> rxminerDevice();
@Native<Pointer<Utf8> Function(Pointer<Utf8>)>(symbol: 'rxminer_check')
external Pointer<Utf8> rxminerCheck(Pointer<Utf8> args);
@Native<Pointer<Utf8> Function(Pointer<Utf8>)>(symbol: 'rxminer_start')
external Pointer<Utf8> rxminerStart(Pointer<Utf8> args);
@Native<Pointer<Utf8> Function()>(symbol: 'rxminer_stop')
external Pointer<Utf8> rxminerStop();
@Native<Pointer<Utf8> Function()>(symbol: 'rxminer_state')
external Pointer<Utf8> rxminerState();
@Native<Void Function(Pointer<Utf8>)>(symbol: 'rxminer_free')
external void rxminerFree(Pointer<Utf8> value);
