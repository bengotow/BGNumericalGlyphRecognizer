# Overview

![image](./Screenshot/screenshot1.png)

The BGNumericalGlyphRecognizer was developed for ScribbleMath for iOS. It extends the glyph recognition in [MultistrokeGestureRecognizer-iOS](https://github.com/bengotow/MultistrokeGestureRecognizer-iOS) to recognize the numbers 0-9, as well as the "minus" character. By itself, the MultistrokeGestureRecognizer-iOS is not sufficient to recognize the numbers 0-9. There are several improvements that were necessary:

- Because the N*Dollar recognizer is orientation-independent, it can't tell the difference between 6 and 9. To address this issue, each glyph drawn on the canvas is mirrored across the X axis and merged with it's inverse to create a stroke that is unique.

- A few characters, such as 5 and 4, are commonly drawn with two separate strokes. A student might start a 5 from the top left, draw a horizontal line, and then draw a separate stroke to create the remainder of the character. BGNumericalGlyphRecognizer includes logic to recognize these glyphs separately, and them merge them into a 5 once they're drawn.

- The N*Dollar recognizer does a poor job of horizontal lines, vertical lines, and zeros. BGNumericalGlyphRecognizer includes logic to recognize these characters through other means. For straight lines, this includes measuring the angle of the line as well as the variance in the angle between points within the line. For zeros, it includes determining that the start and end are near each other, verifying that the head or tail of the line is not straight (which might suggest a 9), and checking that the points are all about the same distance from the midpoint of the shape.


To enable the submission of "answers", the BGNumberCanvas also detects when the user circles existing glyphs in a large "0". In the ScribbleMath app, the student submits their answer by circling it. The app reads the glyphs left to right, and assembles an NSString that represents their submission.

![image](./Screenshot/screenshot2.png)
Example of more complex number recognition

###Sidenote
This code does not work well when numbers are drawn small. I believe this is because the Glyph templates I've created for each number are larger, but I'm not sure. I often have trouble in the simulator, but when I draw on an actual device I create larger numbers and it works fine.



# Setup

To use this code, you must checkout the git submodule located in the Submodules directory. To do this, open a command prompt and `cd` to the top level directory of the repository. Type `git submodule update`, and it will fetch the MultistrokeGestureRecognizer-iOS code.

Most of the interesting code is in BGNumberCanvas, which implements the detection, glyph merging, etc… I know this code isn't beautifully structured—it was written for ScribbleMath, and I've decided to open-source it since I've been asked about it many times since the app's release. 


# Derivative Work

You're encouraged to use this code in your apps—I'd love to know if you find it useful, and I ask that you contribute any improvements you make. Pull requests are welcome.