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

local LrApplication = import 'LrApplication'
local LrApplicationView = import 'LrApplicationView'
local LrDevelopController = import 'LrDevelopController'
local LrDialogs = import 'LrDialogs'
local LrErrors = import 'LrErrors'
local LrFunctionContext = import 'LrFunctionContext'
local LrLogger = import 'LrLogger'
local LrPathUtils = import 'LrPathUtils'
local LrPrefs = import 'LrPrefs'
local LrProgressScope = import 'LrProgressScope'
local LrShell = import 'LrShell'
local LrTasks = import 'LrTasks'

local djpeg = LrPathUtils.child(_PLUGIN.path, "djpeg")
local tempFile = LrPathUtils.child(_PLUGIN.path, "temp.jpg")
local evCurveCoefficent = 2 / math.log(2)

local myLogger = LrLogger('exportLogger')
myLogger:enable("print")

local function print( message )
  myLogger:trace( message )
end

--replace the default assert behavior to use LrErrors.throwUserError
local assertOriginal = assert
local function assert(condition, message)
  if condition ~= true then
    if message == nil then 
      assertOriginal(condition)
    else
      LrErrors.throwUserError(message)
    end
  end
end

local function convertToEV(value)
    return evCurveCoefficent * math.log(value);
end

local luminanceMethods = 
{
  --standard
  function(r,g,b)
    return math.floor(0.2126 * r + 0.7152 * g + 0.0722 * b)
  end,
  --percieved
  function(r,g,b)
    return math.floor(0.299 * r + 0.587 * g + 0.114 * b)
  end,
  --percieved slow
  function(r,g,b)
    return math.floor(math.sqrt(0.299 * r * r + 0.587 * g * g + 0.114 * b * b))
  end,
  --maximum
  function(r,g,b)
    if r > g and r > b then return r
    elseif g > b then return b
    else return b end
  end,
  --red channel
  function(r,g,b)
    return r
  end,
  --green channel
  function(r,g,b)
    return g
  end,
  --blue channel
  function(r,g,b)
    return b
  end
}

local prefs = LrPrefs.prefsForPlugin(_PLUGIN.id)
local deflickerThreshold = prefs.deflickerThreshold
local luminance = luminanceMethods[prefs.luminanceMethod]
local percentile = prefs.percentile

local function decodeJpeg(data)
    local f = io.open(tempFile, "w+")
    f:write(data)
    f:close()
    --call djpeg (from libjpeg) to decode the jpeg to ppm format
    local ppm = io.popen(djpeg.." "..tempFile)
    local magic = ppm:read("*l")
    assert(magic == "P6", "Unsupported PPM format")
    local width = ppm:read("*n")
    local height = ppm:read("*n")
    local depth = ppm:read("*n")
    assert(depth == 255, "Unsupported bit depth")
    --skip line return
    ppm:read("*l")
    --read the data
    local data = ppm:read("*a")
    ppm:close()
    return data, width, height
end

local function computeHistogram(data)
  local histogram = {}
  for i = 1, 256, 1 do
    histogram[i] = 0
  end
  for i = 1, #data - 2, 3 do
    local val = luminance(data:byte(i), data:byte(i + 1), data:byte(i + 2)) + 1
    if val > 256 then val = 256 end
    histogram[val] = histogram[val] + 1
  end
  return histogram, #data / 3
end

local function computePercentile(histogram, total, percentile)
  local stopAt = percentile * total / 100
  local current = 0
  for i = 1, 256, 1 do
    current = current + histogram[i]
    if current > stopAt then
      return i - 1
    end
  end
  return 255
end

local function analyze(photo, progress)
  local median = nil
  local requestError = nil
  while median == nil do
    print("requesting: "..photo:getFormattedMetadata("fileName"))
    local thumb = photo:requestJpegThumbnail(200, 200, function(data, errorMsg)
      if data == nil then
        print(errorMsg)
        requestError = errorMsg
      else
        print("processing: "..photo:getFormattedMetadata("fileName"))
        local histogram, total = computeHistogram(decodeJpeg(data))
        median = computePercentile(histogram, total, percentile)
        print(photo:getFormattedMetadata("fileName")..": "..tostring(median))
      end
    end)
    local timeout = 0
    while median == nil do
      LrTasks.sleep(0.01)
      timeout = timeout + 1
      if progress:isCanceled() then LrErrors.throwCanceled() end
      if timeout >= 40 then break end
      if requestError ~= nil then break end
    end
    thumb = nil
  end
  if median ~= nil then 
    return median
  else
    local msg = "Analysis Failed: "..photo:getFormattedMetadata("fileName")
    if requestError ~= nil then
      msg = msg.."\n"..tostring(requestError)
    end
    LrErrors.throwUserError(msg)
  end
end

local function deflick(context)
  print("deflick started")
  LrDialogs.attachErrorDialogToFunctionContext(context)
  assert(LrApplicationView.getCurrentModuleName() == "develop", "Deflick only works in 'Develop'")
  local cat = LrApplication.activeCatalog();
  local selection = cat:getTargetPhotos();
  local count = #selection
  local max_iterations = 20
  assert(count > 2, "Not enough photos selected")
  
  local progress = LrProgressScope { title="Deflick", functionContext = context }
  
  local startMedian = analyze(selection[1], progress)
  progress:setPortionComplete(1, count)
  
  local endMedian = analyze(selection[#selection], progress)
  progress:setPortionComplete(2, count)
  
  for i,photo in ipairs(selection) do
    if i ~= 1 and i ~= count then
      local lastComputed = -1
      cat:setSelectedPhotos(photo,{})
      local target = startMedian + (endMedian - startMedian) * (i / count)
      for iteration = 1, max_iterations, 1 do
        print("Iteration: "..tostring(iteration))
        local computed = analyze(photo, progress)
        print(photo:getFormattedMetadata("fileName").." Correction: "..tostring(computed).." -> "..tostring(target))
        --if the computed doesn't change, we might need to try again
        local maxRetry = 10
        while computed == lastComputed and maxRetry > 0 do
          LrTasks.sleep(0.1)
          computed = analyze(photo, progress)
          maxRetry = maxRetry - 1
        end
        --if the computed still doesn't change, don't try to change exposure
        if computed ~= lastComputed then
          lastComputed = computed
          if math.abs(target - computed) > deflickerThreshold then
            local offset = nil
            maxRetry = 10
            while offset == nil and maxRetry > 0 do
              LrTasks.sleep(0.1)
              offset = LrDevelopController.getValue("Exposure")
              maxRetry = maxRetry - 1
            end
            if offset == nil then offset = 0 end
            local target = startMedian + (endMedian - startMedian) * (i / count)
            local ev = convertToEV(target) - convertToEV(computed) + offset
            print(photo:getFormattedMetadata("fileName").." Correction (ev): "..tostring(offset).." -> "..tostring(ev))
            LrDevelopController.setValue("Exposure", ev)
          else
            print(photo:getFormattedMetadata("fileName").." Finished")
            break
          end
        else
            print(photo:getFormattedMetadata("fileName").." Preview did not update, re-trying")
        end
        if progress:isCanceled() then LrErrors.throwCanceled() end
      end
    end
    progress:setPortionComplete(i + 1, count)
  end
  
  --restore selection
  cat:setSelectedPhotos(selection[1],selection)
  progress:done()
  print("deflick finished")
end

LrFunctionContext.postAsyncTaskWithContext("deflick", deflick)


