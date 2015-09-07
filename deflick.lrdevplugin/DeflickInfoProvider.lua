--[[--------------------------------------------------------------
 Copyright (C) 2015 David Milligan

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the
Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor,
Boston, MA  02110-1301, USA. 
----------------------------------------------------------------]]

local LrLogger = import 'LrLogger'
local LrPrefs = import 'LrPrefs'
local LrView = import 'LrView'

local myLogger = LrLogger('exportLogger')
myLogger:enable("print")

local function print( message )
  myLogger:trace( message )
end

local DeflickInfoProvider = {}

function DeflickInfoProvider.sectionsForTopOfDialog(viewFactory, propertyTable)
  local prefs = LrPrefs.prefsForPlugin(_PLUGIN.id)
  local bind = LrView.bind
  return 
  {
    {
      title = LOC "$$$/Deflick/Settings/Title=Deflicker Settings",
      viewFactory:row
      {
        viewFactory:static_text { title = LOC "$$$/Deflick/Settings/luminance=Luminance Method: " },
        viewFactory:popup_menu 
        {
          tooltip = LOC "$$$/Deflick/Settings/tooltip/luminance=The method to use to compute luminance from RGB pixels values",
          title = "luminance",
          items = 
          {
            { title = "Standard ITU-R (0.2126 R + 0.7152 G + 0.0722 B)", value = 1 },
            { title = "Percieved Fast (0.299 R + 0.587 G + 0.114 B)", value = 2 },
            { title = "Percieved Slow (sqrt(0.299 R^2 + 0.587 G^2 + 0.114 B^2))", value = 3 },
            { title = "Maximum", value = 4 },
            { title = "Red Channel", value = 5 },
            { title = "Green Channel", value = 6 },
            { title = "Blue Channel", value = 7 },
          },
          value = bind { key = 'luminanceMethod', object = prefs },
        }
      },
      viewFactory:row
      {
        viewFactory:static_text { title = LOC "$$$/Deflick/Settings/percentile=Analysis Percentile: " },
        viewFactory:slider
        {
          tooltip = LOC "$$$/Deflick/Settings/tooltip/percentile=The percentile used to match histograms",
          value = bind { key = 'percentile', object = prefs },
          min = 0,
          max = 100,
          integral = true
        },
        viewFactory:edit_field 
        {
          value = bind { key = 'percentile', object = prefs },
          min = 0,
          max = 100,
          width_in_digits = 4
        }
      },
      viewFactory:row
      {
        viewFactory:static_text { title = LOC "$$$/Deflick/Settings/threshold=Threshold: " },
        viewFactory:slider
        {
          tooltip = LOC "$$$/Deflick/Settings/tooltip/threshold=How close the histogram percentile must be to the target value (low values => slower, better deflicker; high values => faster, worse deflicker)",
          value = bind { key = 'deflickerThreshold', object = prefs },
          min = 1,
          max = 16,
          integral = true
        },
        viewFactory:edit_field
        {
          tooltip = LOC "$$$/Deflick/Settings/tooltip/threshold=How close the histogram percentile must be to the target value (low values => slower, better deflicker; high values => faster, worse deflicker)",
          value = bind { key = 'deflickerThreshold', object = prefs },
          min = 1,
          max = 16,
          width_in_digits = 3
        }
      }
    }
  }
end

function DeflickInfoProvider.sectionsForBottomOfDialog(viewFactory, propertyTable )
  local f = io.open(_PLUGIN:resourceId("LICENSE"), "r")
  local license = f:read("*a")
  f:close()
  return 
  {
    {
      title = LOC "$$$/Deflick/License/Title=License",
      viewFactory:row 
      {
        viewFactory:static_text { title = license }
      }
    }
  }
end

return DeflickInfoProvider