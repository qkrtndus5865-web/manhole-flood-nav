/*
 * 맨홀 경고 진동 키링 — Seeed XIAO nRF52840
 *
 * 이 키링은 자기가 어디 있는지 모른다. GPS 도 지도도 없다.
 * 폰이 "울려라"라고 하면 울릴 뿐이다.
 *
 * 판단을 폰에 몰아둔 이유:
 *   - 폰에는 이미 GPS 가 있다. 여기 또 넣으면 배터리가 하루도 못 간다
 *   - 경고 조건을 바꿀 때 펌웨어를 다시 굽지 않아도 된다
 *   - 키링이 단순해져서 고장 날 데가 없다
 *
 * 굽는 법은 README.md 참고.
 */

#include <bluefruit.h>

#define MOTOR_PIN D0

// 폰이 보내는 명령. 1 바이트면 충분하다.
#define CMD_STOP    0x00
#define CMD_SHORT   0x01   // 맨홀 경고 — 짧게 한 번
#define CMD_LONG    0x02   // 강한 경고 — 길게 한 번
#define CMD_TEST    0x03   // 연결 확인 — 세 번. 시연 때 이걸 쓴다

// 커스텀 서비스. 표준에 맞는 게 없어서 임의로 정했다.
// 앱에서도 같은 값을 써야 한다. 하나라도 다르면 조용히 연결만 되고 아무 일도 안 난다.
const uint8_t SERVICE_UUID[16] = {
  0x9E, 0xCA, 0xDC, 0x24, 0x0E, 0xE5, 0xA9, 0xE0,
  0x93, 0xF3, 0xA3, 0xB5, 0x01, 0x00, 0x40, 0x6E
};
const uint8_t CHAR_UUID[16] = {
  0x9E, 0xCA, 0xDC, 0x24, 0x0E, 0xE5, 0xA9, 0xE0,
  0x93, 0xF3, 0xA3, 0xB5, 0x02, 0x00, 0x40, 0x6E
};

BLEService        buzzService(SERVICE_UUID);
BLECharacteristic buzzChar(CHAR_UUID);

void buzz(int times, int ms) {
  // ponytail: delay 로 충분하다. 진동하는 동안 이 기기가 할 다른 일이 없다.
  //           경고가 겹칠 만큼 맨홀이 촘촘하면 그건 앱의 쿨다운이 막을 문제다.
  for (int i = 0; i < times; i++) {
    digitalWrite(MOTOR_PIN, HIGH);
    delay(ms);
    digitalWrite(MOTOR_PIN, LOW);
    if (i < times - 1) delay(ms);
  }
}

void onWrite(uint16_t conn_hdl, BLECharacteristic* chr, uint8_t* data, uint16_t len) {
  (void) conn_hdl; (void) chr;
  if (len < 1) return;

  switch (data[0]) {
    case CMD_SHORT: buzz(1, 200); break;
    case CMD_LONG:  buzz(1, 600); break;
    case CMD_TEST:  buzz(3, 150); break;
    default:        digitalWrite(MOTOR_PIN, LOW); break;   // 모르는 명령이면 멈춘다
  }
}

void onConnect(uint16_t conn_hdl) {
  (void) conn_hdl;
  buzz(1, 80);   // 연결됐다는 신호. 주머니 안에서도 붙은 걸 알 수 있다
}

void onDisconnect(uint16_t conn_hdl, uint8_t reason) {
  (void) conn_hdl; (void) reason;
  digitalWrite(MOTOR_PIN, LOW);   // 진동 중에 끊기면 계속 떨고 있게 된다
}

void setup() {
  pinMode(MOTOR_PIN, OUTPUT);
  digitalWrite(MOTOR_PIN, LOW);

  Bluefruit.begin();
  Bluefruit.setTxPower(4);
  Bluefruit.setName("ManholeKeyring");
  Bluefruit.Periph.setConnectCallback(onConnect);
  Bluefruit.Periph.setDisconnectCallback(onDisconnect);

  buzzService.begin();

  buzzChar.setProperties(CHR_PROPS_WRITE | CHR_PROPS_WRITE_WO_RESP);
  buzzChar.setPermission(SECMODE_OPEN, SECMODE_OPEN);
  buzzChar.setFixedLen(1);
  buzzChar.setWriteCallback(onWrite);
  buzzChar.begin();

  // 광고. 폰이 이걸 보고 찾아온다.
  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addTxPower();
  Bluefruit.Advertising.addService(buzzService);
  Bluefruit.ScanResponse.addName();

  Bluefruit.Advertising.restartOnDisconnect(true);
  Bluefruit.Advertising.setInterval(32, 244);   // 20ms 로 빠르게 알리다가 152.5ms 로 느려진다
  Bluefruit.Advertising.setFastTimeout(30);
  Bluefruit.Advertising.start(0);               // 0 = 무한. 폰이 올 때까지 계속 기다린다
}

void loop() {
  // 할 일이 없다. 전부 콜백에서 처리한다.
  // 여기서 sd_app_evt_wait() 로 자면 대기 전류가 확 떨어진다.
  sd_app_evt_wait();
}
