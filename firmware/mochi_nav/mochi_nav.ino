/*
 * =====================================================
 *  MOCHI NAV — ESP32-C3 Firmware
 *  Display : SH1106 128×64 via I2C (U8g2 library)
 *  BLE     : Nordic UART Service (NUS)
 *  Speaker : passive buzzer / small speaker on SPEAKER_PIN
 *  Touch   : capacitive TOUCH_PIN
 * =====================================================
 *
 * REQUIRED LIBRARIES (install via Arduino Library Manager):
 *   - U8g2 by oliver                  (search "U8g2")
 *   - ESP32 BLE Arduino               (comes with ESP32 board package)
 *
 * BLE DATA PROTOCOL (sent from Android app):
 *   Navigation : NAV,<direction>,<distance_m>,<eta_min>,<street_name>
 *   Music      : MUSIC,PLAYING,<track>,<artist>,<level_0-100>
 *   Music stop : MUSIC,STOPPED
 *   Test ping  : PING  →  device replies "PONG"
 *
 *   Direction values: TURN_LEFT | TURN_RIGHT | STRAIGHT |
 *                     U_TURN | ARRIVE | ROUNDABOUT_LEFT | ROUNDABOUT_RIGHT
 *
 * TOUCH behaviour:
 *   Short press  (<1.2 s) : toggle audio on/off
 *   Long press   (≥1.2 s) : toggle night/day mode
 * =====================================================
 */

#include <Arduino.h>
#include <Wire.h>
#include <U8g2lib.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

/* ---------- PINS ---------- */
#define SDA_PIN      4
#define SCL_PIN      5
#define SPEAKER_PIN  3
#define TOUCH_PIN    2

/* ---------- DISPLAY ---------- */
// SH1106 128×64, I2C address 0x3C, hardware I2C
U8G2_SSD1306_128X64_NONAME_F_SW_I2C display(U8G2_R0, SCL_PIN, SDA_PIN, U8X8_PIN_NONE);

/* ---------- BLE UUIDs (Nordic UART Service) ---------- */
#define SERVICE_UUID        "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define CHAR_UUID_RX        "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define CHAR_UUID_TX        "6e400003-b5a3-f393-e0a9-e50e24dcca9e"

BLECharacteristic *pTxChar = nullptr;
bool bleConnected = false;

/* ---------- MODES ---------- */
enum Mode { MODE_IDLE, MODE_NAV, MODE_MUSIC };
Mode currentMode = MODE_IDLE;

/* ---------- NAV STATE ---------- */
struct NavState {
  String direction  = "NONE";
  int    distance   = 0;      // metres
  int    eta        = 0;      // minutes
  String street     = "";
  unsigned long lastUpdate = 0;
};
NavState nav;

/* ---------- MUSIC STATE ---------- */
struct MusicState {
  String state  = "STOPPED";
  String track  = "";
  String artist = "";
  int    level  = 0;          // 0-100
  unsigned long lastUpdate = 0;
  int    scrollTrack  = 0;
  int    scrollArtist = 0;
};
MusicState music;

/* ---------- SYSTEM FLAGS ---------- */
bool audioEnabled = true;
bool nightMode    = false;

/* ---------- TIMING ---------- */
const unsigned long NAV_TIMEOUT_MS   = 8000;   // clear nav after 8 s of no update
const unsigned long MUSIC_TIMEOUT_MS = 5000;
const unsigned long ALERT_COOLDOWN   = 3000;   // min ms between audio alerts
unsigned long lastAlertTime = 0;
unsigned long lastBlink     = 0;
bool          blinkState    = false;

/* ---------- FORWARD DECLARATIONS ---------- */
void splashScreen();
void updateMode();
void parseData(String data);
void navUI();
void musicUI();
void idleFace();
void handleTouch();
void beep(int freq, int dur);
void audioAlert();
void sendBLE(String msg);
void drawArrow(const char* dir);
String formatDistance(int metres);

/* ============================================================
 *  BLE SERVER CALLBACKS
 * ============================================================ */
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    bleConnected = true;
  }
  void onDisconnect(BLEServer* pServer) override {
    bleConnected = false;
    // restart advertising so phone can reconnect
    BLEDevice::getAdvertising()->start();
  }
};

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pChar) override {
    String val = pChar->getValue();
    if (!val.isEmpty()) {
      parseData(String(val.c_str()));
    }
  }
};

/* ============================================================
 *  SETUP
 * ============================================================ */
void setup() {  
  Serial.begin(115200);
  delay(2000);
  Serial.println("=== Boot ===");

  pinMode(SPEAKER_PIN, OUTPUT);
  pinMode(TOUCH_PIN, INPUT);

  // I2C + display
  Wire.begin(SDA_PIN, SCL_PIN);
  if (!display.begin()) {
  Serial.println("Display init failed!");
  while(1);
  }
  Serial.println("Display OK");
  display.setContrast(nightMode ? 60 : 200);

  splashScreen();

  // BLE
  BLEDevice::init("Nav_Assistant");
 BLESecurity *pSecurity = new BLESecurity();
  pSecurity->setAuthenticationMode(ESP_LE_AUTH_NO_BOND);
  pSecurity->setCapability(ESP_IO_CAP_NONE);
  pSecurity->setInitEncryptionKey(0);
  BLEServer  *pServer  = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  // RX characteristic — phone writes to this
  BLECharacteristic *pRxChar = pService->createCharacteristic(
    CHAR_UUID_RX,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  pRxChar->setCallbacks(new RxCallbacks());

  // TX characteristic — device notifies phone (for PONG etc.)
  pTxChar = pService->createCharacteristic(
    CHAR_UUID_TX,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pTxChar->addDescriptor(new BLE2902());


  pSecurity->setAuthenticationMode(ESP_LE_AUTH_NO_BOND);
  pSecurity->setCapability(ESP_IO_CAP_NONE);
  pSecurity->setInitEncryptionKey(0);

  pService->start();

  BLEAdvertising *pAdv = BLEDevice::getAdvertising();
  pAdv->addServiceUUID(SERVICE_UUID);
  pAdv->setScanResponse(true);
  pAdv->start();

  Serial.println("BLE advertising started — device name: Mochi_Nav");
}

/* ============================================================
 *  MAIN LOOP
 * ============================================================ */
void loop() {
  handleTouch();
  updateMode();

  switch (currentMode) {
    case MODE_NAV:
      navUI();
      audioAlert();
      break;
    case MODE_MUSIC:
      musicUI();
      break;
    default:
      idleFace();
      break;
  }

  delay(30);   // ~33 fps cap; also debounce BLE callbacks
}

/* ============================================================
 *  MODE MANAGER
 * ============================================================ */
void updateMode() {
  unsigned long now = millis();
  if (nav.lastUpdate   && (now - nav.lastUpdate)   < NAV_TIMEOUT_MS)   { currentMode = MODE_NAV;   return; }
  if (music.lastUpdate && (now - music.lastUpdate) < MUSIC_TIMEOUT_MS) { currentMode = MODE_MUSIC; return; }
  currentMode = MODE_IDLE;
}

/* ============================================================
 *  DATA PARSING
 *  Protocol: NAV,<dir>,<dist>,<eta>,<street>
 *            MUSIC,PLAYING,<track>,<artist>,<level>
 *            MUSIC,STOPPED
 *            PING
 * ============================================================ */
void parseData(String data) {
  data.trim();
  Serial.print("RX: "); Serial.println(data);

  // --- PING ---
  if (data == "PING") {
    sendBLE("PONG");
    return;
  }

  // --- NAV ---
  if (data.startsWith("NAV,")) {
    // Tokenise by comma
    String parts[5];
    int count = 0, start = 4;
    for (int i = 4; i <= data.length() && count < 5; i++) {
      if (i == (int)data.length() || data[i] == ',') {
        parts[count++] = data.substring(start, i);
        start = i + 1;
      }
    }
    if (count >= 2) {
      nav.direction = parts[0];
      nav.distance  = parts[1].toInt();
      nav.eta       = (count >= 3) ? parts[2].toInt() : 0;
      nav.street    = (count >= 4) ? parts[3] : "";
      nav.lastUpdate = millis();
    }
    return;
  }

  // --- MUSIC ---
  if (data.startsWith("MUSIC,")) {
    String rest = data.substring(6);
    if (rest.startsWith("STOPPED")) {
      music.state = "STOPPED";
      music.lastUpdate = 0;   // expire immediately
      return;
    }
    if (rest.startsWith("PLAYING,")) {
      String payload = rest.substring(8);
      int c1 = payload.indexOf(',');
      int c2 = payload.indexOf(',', c1 + 1);
      music.state  = "PLAYING";
      music.track  = (c1 > 0)          ? payload.substring(0, c1)         : payload;
      music.artist = (c2 > c1)         ? payload.substring(c1 + 1, c2)    : "";
      music.level  = (c2 >= 0)         ? payload.substring(c2 + 1).toInt(): 50;
      music.scrollTrack  = 0;
      music.scrollArtist = 0;
      music.lastUpdate   = millis();
    }
    return;
  }

  Serial.println("  (unrecognised command)");
}

/* ============================================================
 *  TOUCH HANDLER
 *  Short tap  → toggle audio
 *  Long press → toggle night mode
 * ============================================================ */
void handleTouch() {
  static unsigned long touchStart = 0;
  static bool          held       = false;

  bool pressed = digitalRead(TOUCH_PIN);

  if (pressed && !touchStart) {
    touchStart = millis();
    held = false;
  }

  if (pressed && touchStart && !held && (millis() - touchStart >= 1200)) {
    // Long press fired
    held = true;
    nightMode = !nightMode;
    display.setContrast(nightMode ? 60 : 200);
    beep(600, 120);
  }

  if (!pressed && touchStart) {
    if (!held) {
      // Short tap released
      audioEnabled = !audioEnabled;
      beep(audioEnabled ? 900 : 500, 80);
    }
    touchStart = 0;
    held = false;
  }
}

/* ============================================================
 *  NAV UI
 *
 *  Layout (128 × 64):
 *   Row 0  (y=0..15)  : street name (small font, scrolling)
 *   Row 1  (y=16..47) : direction arrow (large, centred)
 *   Row 2  (y=48..55) : distance  e.g. "320 m"
 *   Row 3  (y=56..63) : ETA       e.g. "ETA 7 min"  + BLE dot
 * ============================================================ */
void navUI() {
  display.clearBuffer();

  // ---- Street name (top row, small, scrolling if long) ----
  display.setFont(u8g2_font_5x7_tr);
  String street = nav.street.length() > 0 ? nav.street : "Navigating...";
  int streetW = display.getStrWidth(street.c_str());
  static int streetScroll = 0;
  if (streetW <= 128) {
    display.drawStr(0, 7, street.c_str());
    streetScroll = 0;
  } else {
    display.drawStr(-streetScroll, 7, street.c_str());
    streetScroll = (streetScroll + 1) % (streetW + 20);
  }

  // ---- Direction arrow (centre region 16..47) ----
  drawArrow(nav.direction.c_str());

  // ---- Distance (row 48-55) ----
  display.setFont(u8g2_font_7x13B_tr);
  String distStr = formatDistance(nav.distance);
  int dw = display.getStrWidth(distStr.c_str());
  display.drawStr((128 - dw) / 2, 58, distStr.c_str());

  // ---- ETA (bottom right) ----
  if (nav.eta > 0) {
    display.setFont(u8g2_font_5x7_tr);
    String etaStr = "ETA " + String(nav.eta) + "m";
    int ew = display.getStrWidth(etaStr.c_str());
    display.drawStr(128 - ew, 63, etaStr.c_str());
  }

  // ---- BLE connected dot (top-right corner) ----
  if (bleConnected) {
    display.drawDisc(124, 4, 3);
  }

  display.sendBuffer();
}

/* ============================================================
 *  DRAW DIRECTION ARROW
 *  Draws inside the region y=16..47 (31 px tall), centred x
 * ============================================================ */
void drawArrow(const char* dir) {
  String d = String(dir);
  // All coordinates relative to a 30×30 bounding box centred at (64, 31)
  const int cx = 64, cy = 31, s = 13;

  if (d == "TURN_LEFT") {
    // Arrow pointing left
    display.drawTriangle(cx - s, cy,  cx + s/2, cy - s,  cx + s/2, cy + s);
    display.drawBox(cx - s/4, cy - s/4, s, s/2);
  } else if (d == "TURN_RIGHT") {
    display.drawTriangle(cx + s, cy,  cx - s/2, cy - s,  cx - s/2, cy + s);
    display.drawBox(cx - s*3/4, cy - s/4, s, s/2);
  } else if (d == "STRAIGHT") {
    display.drawTriangle(cx, cy - s,  cx - s, cy + s/2,  cx + s, cy + s/2);
    display.drawBox(cx - s/4, cy + s/2, s/2, s/2);
  } else if (d == "U_TURN") {
    // U-turn arc with arrow
    display.drawCircle(cx + 4, cy, 8, U8G2_DRAW_UPPER_RIGHT | U8G2_DRAW_LOWER_RIGHT);
    display.drawLine(cx + 4, cy - 8, cx - 4, cy - 8);
    display.drawTriangle(cx - 4, cy - 12,  cx - 4, cy - 4,  cx - 10, cy - 8);
  } else if (d == "ARRIVE") {
    // Destination flag / checkered box
    display.drawFrame(cx - s/2, cy - s, s, s * 2);
    display.drawLine(cx - s/2, cy, cx + s/2, cy);
    display.drawLine(cx, cy - s, cx, cy + s);
    display.drawBox(cx - s/2, cy - s, s/2, s/2);   // top-left filled
    display.drawBox(cx,       cy,     s/2, s/2);   // bottom-right filled
  } else if (d == "ROUNDABOUT_LEFT" || d == "ROUNDABOUT_RIGHT") {
    display.drawCircle(cx, cy, 10);
    if (d == "ROUNDABOUT_LEFT") {
      display.drawTriangle(cx - 10, cy,  cx - 4, cy - 8,  cx - 4, cy + 8);
    } else {
      display.drawTriangle(cx + 10, cy,  cx + 4, cy - 8,  cx + 4, cy + 8);
    }
  } else {
    // Default: straight-ish dashes for NONE/unknown
    display.setFont(u8g2_font_7x13B_tr);
    display.drawStr(cx - 6, cy + 5, "--");
  }
}

/* ============================================================
 *  MUSIC UI
 *
 *  Layout:
 *   y=0..9  : "NOW PLAYING" label
 *   y=10..21: track name  (scrolling)
 *   y=22..31: artist name (scrolling)
 *   y=33..63: visualiser bars
 * ============================================================ */
void musicUI() {
  display.clearBuffer();

  // Header
  display.setFont(u8g2_font_5x7_tr);
  display.drawStr(0, 8, "NOW PLAYING");

  // Track name
  display.setFont(u8g2_font_6x12_tr);
  int tw = display.getStrWidth(music.track.c_str());
  if (tw <= 128) {
    display.drawStr(0, 20, music.track.c_str());
    music.scrollTrack = 0;
  } else {
    display.drawStr(-music.scrollTrack, 20, music.track.c_str());
    music.scrollTrack = (music.scrollTrack + 1) % (tw + 20);
  }

  // Artist name
  display.setFont(u8g2_font_5x7_tr);
  int aw = display.getStrWidth(music.artist.c_str());
  if (aw <= 128) {
    display.drawStr(0, 30, music.artist.c_str());
    music.scrollArtist = 0;
  } else {
    display.drawStr(-music.scrollArtist, 30, music.artist.c_str());
    music.scrollArtist = (music.scrollArtist + 1) % (aw + 20);
  }

  // Visualiser (6 bars, seeded pseudo-random for smooth animation)
  int barH[6];
  int base = music.level / 5 + 4;
  for (int i = 0; i < 6; i++) {
    // Use a simple deterministic wave instead of random()
    barH[i] = base + (int)(base * 0.6 * sin((millis() / 200.0) + i * 1.1));
    barH[i] = constrain(barH[i], 3, 28);
  }
  for (int i = 0; i < 6; i++) {
    int x = 10 + i * 18;
    display.drawBox(x, 63 - barH[i], 10, barH[i]);
  }

  display.sendBuffer();
}

/* ============================================================
 *  IDLE FACE
 *  Simple blinking eyes
 * ============================================================ */
void idleFace() {
  if (millis() - lastBlink > 1400) {
    blinkState = !blinkState;
    lastBlink  = millis();
  }

  display.clearBuffer();

  if (blinkState) {
    // Closed eyes (line)
    display.drawHLine(38, 30, 12);
    display.drawHLine(78, 30, 12);
  } else {
    // Open eyes (filled circles)
    display.drawDisc(44, 28, 7);
    display.drawDisc(84, 28, 7);
    // Pupils
    display.setDrawColor(0);
    display.drawDisc(46, 26, 2);
    display.drawDisc(86, 26, 2);
    display.setDrawColor(1);
  }

  // Mouth
  display.drawHLine(52, 44, 24);
  display.drawPixel(51, 43);
  display.drawPixel(76, 43);

  // BLE status
  display.setFont(u8g2_font_5x7_tr);
  if (bleConnected) {
    display.drawStr(0, 63, "BLE OK");
  } else {
    display.drawStr(0, 63, "Waiting...");
  }

  display.sendBuffer();
}

/* ============================================================
 *  AUDIO ALERT
 *  Fires at most once per ALERT_COOLDOWN when near a turn
 * ============================================================ */
void audioAlert() {
  if (!audioEnabled) return;
  if (nav.distance <= 0 || nav.distance > 30) return;
  if (millis() - lastAlertTime < ALERT_COOLDOWN) return;

  // Two short beeps for imminent turn
  beep(1200, 100);
  delay(80);
  beep(1200, 100);
  lastAlertTime = millis();
}

/* ============================================================
 *  BEEP
 *  Uses ESP32 Arduino Core v3 ledc API
 * ============================================================ */
void beep(int freq, int dur) {
  if (!audioEnabled) return;
  ledcAttachChannel(SPEAKER_PIN, freq, 8, 0);
  ledcWrite(SPEAKER_PIN, 128);
  delay(dur);
  ledcWrite(SPEAKER_PIN, 0);
  ledcDetach(SPEAKER_PIN);
}

/* ============================================================
 *  BLE TRANSMIT (notify phone)
 * ============================================================ */
void sendBLE(String msg) {
  if (!bleConnected || !pTxChar) return;
  pTxChar->setValue(msg.c_str());
  pTxChar->notify();
}

/* ============================================================
 *  FORMAT DISTANCE
 *  < 1000 m  → "320 m"
 *  >= 1000 m → "1.2 km"
 * ============================================================ */
String formatDistance(int metres) {
  if (metres < 1000) return String(metres) + " m";
  float km = metres / 1000.0f;
  char buf[10];
  snprintf(buf, sizeof(buf), "%.1f km", km);
  return String(buf);
}

/* ============================================================
 *  SPLASH SCREEN
 * ============================================================ */
void splashScreen() {
  display.clearBuffer();
  display.setFont(u8g2_font_logisoso16_tr);
  display.drawStr(28, 28, "NAV");
  display.setFont(u8g2_font_7x13B_tr);
  display.drawStr(16, 46, "ASST");
  display.setFont(u8g2_font_5x7_tr);
  display.drawStr(28, 60, "v2.0  by you :)");
  display.sendBuffer();
  beep(1200, 120);
  delay(80);
  beep(1500, 120);
  delay(1400);
}
