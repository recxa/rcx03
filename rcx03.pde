import javax.swing.JFrame;
import javax.swing.JComponent;
import java.awt.Robot;
import java.awt.Rectangle;
import java.awt.AWTException;
import java.awt.Toolkit;
import java.awt.image.BufferedImage;
import processing.core.PImage;
import java.awt.event.MouseAdapter;
import java.awt.event.MouseEvent;
import processing.awt.PSurfaceAWT;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.io.File;
import oscP5.*;
import netP5.*;
import controlP5.*;

int cols = 32;
int rows = 32;
int scale = 10;
boolean[][] grid = new boolean[cols][rows];
boolean[][] nextGrid = new boolean[cols][rows];

Robot robot;
JFrame window;
int previousX, previousY;
boolean isDragging = false;

boolean erasing = false;

boolean mouseOver = false;
float normalizedX = 0.0;
float normalizedY = 0.0;

ControlP5 cp5;
Toggle playPauseToggle;
Toggle immortalToggle;
Button nextStepButton, randomizeButton;
Slider mixSlider;
Textlabel mixLabel;
Slider bitcrushMixSlider;
Slider sampleRateMixSlider;
Numberbox tempoNumberbox;
boolean isPlaying = true;
boolean immortal = false;
boolean edgeWrapped = false;
Textlabel edgeWrapLabel;
int tempo = 120;
int lastUpdateTime = 0;

color disabledColor = color(50); // A dark gray color
color bcColor = color(100, 0, 0); // A dark red 
color srColor = color(0, 0, 100); // A dark blue color
color bgColor = color(0, 0, 0, 0);

color gridlineColor = disabledColor;

void setup() {
  size(320, 352, JAVA2D);
  PSurfaceAWT surf = (PSurfaceAWT) getSurface();
  PSurfaceAWT.SmoothCanvas canvas = (PSurfaceAWT.SmoothCanvas) surf.getNative();
  window = (JFrame) canvas.getFrame();

  try {
    robot = new Robot();
  } catch (AWTException e) {
    e.printStackTrace();
    exit();
  }

  window.dispose();
  window.setUndecorated(true);
  window.setVisible(true);
  window.setBackground(new java.awt.Color(255, 0, 0)); // Fully transparent background
  //window.setOpacity(1f); // Slightly visible window
  //window.setOpaque(false);

  window.setSize(width, height);
  noStroke();
  
  cp5 = new ControlP5(this);
  
  // Initialize OSC communication
  oscP5 = new OscP5(this, 12000); // Listening port for incoming OSC (if needed)
  maxAddress = new NetAddress("127.0.0.1", 7400); // IP and port for Max/MSP
  
  randomizeGrid();
  
  canvas.addMouseListener(new MouseAdapter() {
    public void mousePressed(MouseEvent e) {
      if(e.getY() < 50 && e.getButton() == MouseEvent.BUTTON1) {
        println("righttt!");
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
  
  // Play/Pause Toggle Button
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
                          lastUpdateTime = millis();
                          sendFirstColumnOSC();
                        }
                      });
                      
  // Play/Pause Toggle Button
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

  // Next Step Button
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

  // Randomize Button
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

  // Mix Slider
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

OscP5 oscP5;
NetAddress maxAddress;

float playhead;
int subdivision = 2;
int lastIndex = 0;
int xIndex = 0;
int yIndex = 0;
int lastX = 0;
int lastY = 0;

float mix = 0.0;

void sendFirstColumnOSC() {
  StringBuilder columnDataL = new StringBuilder();
  StringBuilder columnDataR = new StringBuilder();
  
  if (isPlaying) {
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < rows; j++) {
        columnDataL.append(grid[i][lastIndex] ? "1 " : "0 ");
        columnDataR.append(grid[lastIndex][i] ? "1 " : "0 ");
      }
    }
  } else {
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < rows; j++) {
        columnDataL.append(grid[i][j] ? "1 " : "0 ");
        columnDataR.append(grid[j][i] ? "1 " : "0 ");
      }
    }
  }

  OscMessage msgL = new OscMessage("/generationL");
  OscMessage msgR = new OscMessage("/generationR");
  
  msgL.add(columnDataL.toString());
  msgR.add(columnDataR.toString());
  
  oscP5.send(msgL, maxAddress);
  oscP5.send(msgR, maxAddress);
}

void sendMixOSC() {
  OscMessage msg = new OscMessage("/mix");

  msg.add(mixSlider.getValue());

  oscP5.send(msg, maxAddress);
}

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