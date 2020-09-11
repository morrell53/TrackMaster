int solenoid1       = 13; //Solenoid1 is connected to pin9
int solenoid2       = 12;
int solenoid3       = 11;
int solenoid4       = 10;
int IRbeamPower     = 2;//IR LED connected to pin 7
int Beam_Break      = 3;//IR receiver connected to pin 6
int AirValve        = 4;

int openTime = 1000;

String serialReceived;
char State;

bool BreakStatus = false;
boolean receiverState;

void setup() {

  pinMode(solenoid1, OUTPUT);
  pinMode(solenoid2, OUTPUT);
  pinMode(solenoid3, OUTPUT);
  pinMode(solenoid4, OUTPUT);

  pinMode(IRbeamPower, OUTPUT);
  pinMode(Beam_Break, INPUT);
  pinMode(AirValve, OUTPUT);

  Serial.begin(9600); //open serial port and set rate to 9600 baud
  
}

void loop() {
  // put your main code here, to run repeatedly:
  if (Serial.available() >0) {
    
    serialReceived = Serial.readStringUntil('\n');
    State = serialReceived.charAt(0);
    switch (State) {
      case '1':
        digitalWrite(solenoid1, HIGH); 
        delay(openTime);
        digitalWrite(solenoid1, LOW);
      case '2':
        digitalWrite(solenoid2, HIGH);
        delay(openTime);
        digitalWrite(solenoid2, LOW);
      case '3':
        digitalWrite(solenoid3, HIGH);
        delay(openTime);
        digitalWrite(solenoid3, LOW);
      case '4':
        digitalWrite(solenoid4, HIGH);
        delay(openTime);
        digitalWrite(solenoid4, LOW);
      case '5':
        MonitorBeam();
        break;
      case '6':
        digitalWrite(AirValve, HIGH);
        delay(openTime);
        digitalWrite(AirValve, LOW);
    }
  }
}

void MonitorBeam(){
  tone(IRbeamPower,38000);
  delay(50);
  while (!BreakStatus){
    if (Serial.available() >0) {
      digitalWrite(IRbeamPower, LOW);
      Serial.flush();
      BreakStatus = 0;
      return;
    }
    receiverState = digitalRead(Beam_Break);
    if (receiverState == HIGH) { // beam interrupted
      BreakStatus = true;
      digitalWrite(AirValve, HIGH);
      Serial.println('B');
      delay(200);
      digitalWrite(AirValve, LOW);
    }
    else { // beam detected
      digitalWrite(AirValve, LOW);
    }
  }
  noTone(IRbeamPower);
  BreakStatus = false;
}

