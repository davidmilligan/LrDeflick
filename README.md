# LrDeflick
Adobe Lightroom plugin for deflickering (uniform exposure) image sequences

This plugin analyzes the histograms of images in a sequence in order to give them all a uniform exposure thus removing 'flicker' common to, for example, timelapse sequences in changing lighting conditions.

How to use
----------

- Select the images you want to deflicker in the Develop module and then run the script (File > Plug-In Extras > Deflick)
- The exposure will be matched to a linear target value from the first selected photo to the last (the first and last photos themselves will not be altered)

LrDeflick requires the djpeg utility from libjpeg (https://github.com/LuaDist/libjpeg). Compile it for your system and place it in the plugin folder (it should be called 'djpeg' on mac and 'djpeg.exe' on windows).

