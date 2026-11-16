import 'package:rxminer/rxminer.dart';

void main() {
  final device = RxMiner.device();
  print('${device.summary}, JIT ${device.jit ? 'available' : 'unavailable'}');
  print(
    'threads: ${RxMiner.check(['-o', 'pool.example.com:3333', '-u', 'x']).threads}',
  );
}
