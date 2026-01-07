// IMPORTS
import javax.swing.JFrame;
import java.awt.Robot;
import java.awt.AWTException;
import java.awt.event.MouseAdapter;
import java.awt.event.MouseEvent;
import processing.awt.PSurfaceAWT;
import oscP5.*;
import netP5.*;
import controlP5.*;

// FRAME SETUP
Robot robot;
JFrame window;

// GUI SETUP
ControlP5 cp5;
Toggle playPauseToggle;
Toggle immortalToggle;
Button nextStepButton, randomizeButton;
Slider mixSlider;
Textlabel mixLabel;
color disabledColor = color(50); // A dark gray color

// MOUSE SETUP
int previousX, previousY;
boolean isDragging = false;

// SIM SETUP
boolean isPlaying = true;
boolean immortal = false;
int cols = 32;
int rows = 32;
int scale = 10;
boolean[][] grid = new boolean[cols][rows];
boolean[][] nextGrid = new boolean[cols][rows];
int subdivision = 2;
int lastIndex = 0;

// FREQ SCALE SETUP
int[][] logMapBands = null; // [1024][2] startBin,endBin
final float DEFAULT_SR = 44100.0; // match your Max SR if different

// OSC SETUP
OscP5 oscP5;
NetAddress maxAddress;

void setup() {
  // FRAME SETUP
  size(320, 352, JAVA2D);
  PSurfaceAWT surf = (PSurfaceAWT) getSurface();
  PSurfaceAWT.SmoothCanvas canvas = (PSurfaceAWT.SmoothCanvas) surf.getNative();
  window = (JFrame) canvas.getFrame();
  window.dispose();
  window.setUndecorated(true);
  window.setVisible(true);
  window.setBackground(new java.awt.Color(255, 0, 0)); // Fully transparent background
  window.setSize(width, height);
  noStroke();
  cp5 = new ControlP5(this); 
  try {
    robot = new Robot();
  } catch (AWTException e) {
    e.printStackTrace();
    exit();
  }
  
  // OSC SETUP
  oscP5 = new OscP5(this, 12000); // Listening port for incoming OSC (if needed)
  maxAddress = new NetAddress("127.0.0.1", 7400); // IP and port for Max/MSP
  
  // SIM SETUP
  randomizeGrid();
  buildLogMap(20.0, 20000.0, 44100.0);  // or use sampleRate if dynamic
  
  // MOUSE SETUP
  canvas.addMouseListener(new MouseAdapter() {
    public void mousePressed(MouseEvent e) {
      if(e.getY() < 50 && e.getButton() == MouseEvent.BUTTON1) {
        isDragging = true;
        previousX = e.getXOnScreen();
        previousY = e.getYOnScreen();
      }
    }

    public void mouseReleased(MouseEvent e) {
      if (e.getButton() == MouseEvent.BUTTON1) {
        isDragging = false;
      }
    }
  });
  
  canvas.addMouseMotionListener(new MouseAdapter() {
    public void mouseDragged(MouseEvent e) {
      if (isDragging) {
        int dx = e.getXOnScreen() - previousX;
        int dy = e.getYOnScreen() - previousY;
        window.setLocation(window.getX() + dx, window.getY() + dy);

        previousX = e.getXOnScreen();
        previousY = e.getYOnScreen();
      }
      else if (e.getButton() == MouseEvent.BUTTON1 && e.getY() < 320 && e.getY() > 0 && e.getX() < 320 && e.getX() > 0) {
        grid[floor(e.getX() / 10) % 32][floor(e.getY() / 10) % 32] = true;
        sendFirstColumnOSC();
      }
      else if (mouseButton == RIGHT && e.getY() < 320 && e.getY() > 0 && e.getX() < 320 && e.getX() > 0) {
        grid[floor(e.getX() / 10) % 32][floor(e.getY() / 10) % 32] = false;
        sendFirstColumnOSC();
      }
    }
  });
  
  // PLAY/PAUSE TOGGLE BUTTON
  playPauseToggle = cp5.addToggle("Play/Pause")
                      .setPosition(0, 320)
                      .setSize(30, 30)
                      .setColorForeground(color(200))
                      .setColorBackground(color(100))
                      .setColorActive(color(255, 255, 9))
                      .setValue(isPlaying ? 1 : 0)
                      .onChange(new CallbackListener() {
                        public void controlEvent(CallbackEvent event) {
                          isPlaying = !isPlaying;
                          sendFirstColumnOSC();
                        }
                      });
                      
  // AUTO-STEP TOGGLE BUTTON
  immortalToggle = cp5.addToggle("Immortal")
                      .setPosition(30, 320)
                      .setSize(30, 30)
                      .setColorForeground(color(200))
                      .setColorBackground(color(100))
                      .setColorActive(color(255, 255, 9))
                      .setValue(immortal ? 1 : 0)
                      .onChange(new CallbackListener() {
                        public void controlEvent(CallbackEvent event) {
                          immortal = !immortal;
                        }
                      });

  // NEXT STEP BUTTON
  nextStepButton = cp5.addButton("Next Step")
                     .setPosition(60, 320)
                     .setSize(60, 30)
                     .setColorForeground(color(200))
                     .setColorBackground(color(100))
                     .setColorActive(color(255))
                     .onPress(new CallbackListener() {
                       public void controlEvent(CallbackEvent event) {
                         nextStepButton.setColorLabel(color(0));
                         calculateNextGeneration();
                       }
                     })
                     .onRelease(new CallbackListener() {
                       public void controlEvent(CallbackEvent event) {
                         nextStepButton.setColorLabel(color(255));
                       }
                     });

  // RANDOMIZE BUTTON (LMB = RAND, RMB = CLEAR)
  randomizeButton = cp5.addButton("Randomize")
                     .setPosition(120, 320)
                     .setSize(60, 30)
                     .setColorForeground(color(200))
                     .setColorBackground(color(100))
                     .setColorActive(color(255))
                     .onPress(new CallbackListener() {
                       public void controlEvent(CallbackEvent event) {
                         switch (mouseButton) {
                           case LEFT: randomizeGrid(); break;
                           case RIGHT: clearGrid(); break;
                           //case CENTER: resetGrid(3); break;
                         }
                         randomizeButton.setColorLabel(color(0));
                       }
                     })
                     .onRelease(new CallbackListener() {
                       public void controlEvent(CallbackEvent event) {
                         randomizeButton.setColorLabel(color(255));
                       }
                     });

  // MIX SLIDER
  mixSlider = cp5.addSlider("Mixer")
                .setPosition(180, 320)
                .setColorForeground(color(200))
                .setColorBackground(disabledColor)
                .setColorActive(color(255))
                .setSize(140, 30)
                .setRange(0, 1)
                .setValue(0.8)
                .setLabelVisible(false)
                .onChange(new CallbackListener() {
                  public void controlEvent(CallbackEvent event) {
                    sendMixOSC();
                  }
                });
                
  mixLabel = cp5.addTextlabel("Mix")
             .setText("MIX")
             .setPosition(180, 325);
}



// GUI FUNCTIONS
void dimSlider(Slider slider) {
  slider.setColorForeground(color(50));
  slider.setColorBackground(color(50));
  slider.setColorActive(color(50));
  slider.setLabelVisible(false);
}

void unDimSlider(Slider slider, color foregroundColor, color backgroundColor, color activeColor) {
  slider.setColorForeground(foregroundColor);
  slider.setColorBackground(backgroundColor);
  slider.setColorActive(activeColor);
  slider.setLabelVisible(true);
}



// SIM FUNCTIONS
void randomizeGrid() {
  for (int i = 0; i < cols; i++) {
    for (int j = 0; j < rows; j++) {
      grid[i][j] = random(1) > 0.5;
    }
  }
  sendFirstColumnOSC();
}

void clearGrid() {
  for (int i = 0; i < cols; i++) {
    for (int j = 0; j < rows; j++) {
      grid[i][j] = false;
    }
  }
  sendFirstColumnOSC();
}

void calculateNextGeneration() {
  for (int i = 0; i < cols; i++) {
    for (int j = 0; j < rows; j++) {
      int neighbors = countNeighbors(i, j);
      if (grid[i][j]) {
        if (neighbors < 2 || neighbors > 3) {
          nextGrid[i][j] = false;
        } else {
          nextGrid[i][j] = true;
        }
      } else {
        if (neighbors == 3) {
          nextGrid[i][j] = true;
        } else {
          nextGrid[i][j] = false;
        }
      }
    }
  }

  // Swap grids
  boolean[][] temp = grid;
  grid = nextGrid;
  nextGrid = temp;
  
  sendFirstColumnOSC();
}

int countNeighbors(int x, int y) {
  int count = 0;
  for (int i = -1; i <= 1; i++) {
    for (int j = -1; j <= 1; j++) {
      int col = (x + i + cols) % cols;
      int row = (y + j + rows) % rows;
      if (grid[col][row]) {
        count++;
      }
    }
  }
  if (grid[x][y]) count--; // Subtract self count
  return count;
}



// FREQ SCALE FUNCTIONS
void ensureLogMap() {
  if (logMapBands == null || logMapBands.length != 1024) {
    // fMin 20 Hz, fMax limited by Nyquist;
    float nyq = DEFAULT_SR / 2.0;
    buildLogMap(20.0, min(20000.0, nyq), DEFAULT_SR);
  }
}

void buildLogMap(float fMin, float fMax, float sampleRate) {
  float nyquist = sampleRate / 2.0;
  float octaves = log(fMax / fMin) / log(2);
  logMapBands = new int[1024][2];

  for (int i = 0; i < 1024; i++) {
    float p1 = i     / 1024.0;
    float p2 = (i+1) / 1024.0;

    float f1 = fMin * pow(2, p1 * octaves);
    float f2 = fMin * pow(2, p2 * octaves);

    int bin1 = round(f1 / nyquist * 1023);
    int bin2 = round(f2 / nyquist * 1023);

    // order + clamp
    int s = constrain(min(bin1, bin2), 0, 1023);
    int e = constrain(max(bin1, bin2), 0, 1023);
    logMapBands[i][0] = s;
    logMapBands[i][1] = e;
  }
}



// DRAW FUNCTION (GRID AND RED BOTTOMLINE)
void draw() {
  background(255, 0, 0);
  for (int i = 0; i < cols; i++) {
    for (int j = 0; j < rows; j++) {
      if (grid[i][j]) {
        if((i == lastIndex || j == lastIndex) && isPlaying) { fill(255, 255, 0); } else { fill(255); }
      } else {
        fill(0);
      }
      rect(i * scale, j * scale, scale, scale);
    }
  }
}



// OSC SENDER (GRID DATA)
void sendFirstColumnOSC() {
  ensureLogMap();

  // Gather 1024 grid cells into flat arrays (same as before)
  boolean[] flatL = new boolean[1024];
  boolean[] flatR = new boolean[1024];
  int idx = 0;

  if (isPlaying) {
    // 32x32 slice (row/col @ lastIndex) → 1024 cells
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < rows; j++) {
        flatL[idx] = grid[i][lastIndex];
        flatR[idx] = grid[lastIndex][i];
        idx++;
      }
    }
  } else {
    // full grid (row-major) and its diagonal-inverted readout
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < rows; j++) {
        flatL[idx] = grid[i][j];
        flatR[idx] = grid[j][i];
        idx++;
      }
    }
  }

  // Paint bins from cells using octave-bucket bands
  // out* are per-FFT-bin 0..1023
  int[] outL = new int[1024];
  int[] outR = new int[1024];

  for (int cell = 0; cell < 1024; cell++) {
    if (flatL[cell]) {
      int s = logMapBands[cell][0], e = logMapBands[cell][1];
      for (int b = s; b <= e; b++) outL[b] = 1;
    }
    if (flatR[cell]) {
      int s = logMapBands[cell][0], e = logMapBands[cell][1];
      for (int b = s; b <= e; b++) outR[b] = 1;
    }
  }

  // Serialize bins in order (what Max writes into buffer indices 0..1023)
  StringBuilder columnDataL = new StringBuilder();
  StringBuilder columnDataR = new StringBuilder();
  for (int b = 0; b < 1024; b++) {
    columnDataL.append(outL[b]).append(' ');
    columnDataR.append(outR[b]).append(' ');
  }

  OscMessage msgL = new OscMessage("/generationL");
  OscMessage msgR = new OscMessage("/generationR");
  msgL.add(columnDataL.toString());
  msgR.add(columnDataR.toString());
  oscP5.send(msgL, maxAddress);
  oscP5.send(msgR, maxAddress);
}



// OSC SENDER (MIX)
void sendMixOSC() {
  OscMessage msg = new OscMessage("/mix");

  msg.add(mixSlider.getValue());

  oscP5.send(msg, maxAddress);
}



// OSC RECIEVER (TEMPO SYNC)
void oscEvent(OscMessage msg) {
  int val = floor(msg.get(0).floatValue() * cols * subdivision) % cols;
  if(val != lastIndex) {
    if (val == 0 && immortal) {
        calculateNextGeneration();
        sendFirstColumnOSC();
    }
    if (isPlaying) {
      lastIndex = val;
      sendFirstColumnOSC();
    }
  }
}
