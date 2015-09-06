
local LrApplication = import 'LrApplication'
local LrApplicationView = import 'LrApplicationView'
local LrDevelopController = import 'LrDevelopController'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrLogger = import 'LrLogger'
local LrPathUtils = import 'LrPathUtils'
local LrProgressScope = import 'LrProgressScope'
local LrShell = import 'LrShell'
local LrTasks = import 'LrTasks'

local djpeg = LrPathUtils.child(_PLUGIN.path, "djpeg")
local tempFile = LrPathUtils.child(_PLUGIN.path, "temp.jpg")
local evCurveCoefficent = 2 / math.log(2)
local deflickerThreshold = 2

local myLogger = LrLogger('exportLogger')
myLogger:enable("print")

local function print( message )
  myLogger:trace( message )
end

local function convertToEV(value)
    return evCurveCoefficent * math.log(value);
end

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
  for i = 1, #data, 1 do
    local val = data:byte(i) + 1
    histogram[val] = histogram[val] + 1
  end
  return histogram, #data
end

local function computePercentile(histogram, total, percentile)
  local stopAt = percentile * total / 100
  local current = 0
  for i = 1, 256, 1 do
    current = current + histogram[i]
    if current > stopAt then
      return i
    end
  end
end

local function analyze(photo)
  local done = false
  local error = false
  while done == false do
    print("requesting: "..photo:getFormattedMetadata("fileName"))
    local thumb = photo:requestJpegThumbnail(200, 200, function(data, errorMsg)
      if data == nil then
        print(errorMsg)
        error = true
      elseif done == false then
        print("processing: "..photo:getFormattedMetadata("fileName"))
        local histogram, total = computeHistogram(decodeJpeg(data))
        photo.deflickMedian = computePercentile(histogram, total, 50)
        print(photo:getFormattedMetadata("fileName").." median: "..tostring(photo.deflickMedian))
        done = true
      end
    end)
    local timeout = 0
    while done == false do
      LrTasks.sleep(0.01)
      timeout = timeout + 1
      if progress:isCanceled() then return end
      if timeout >= 40 then break end
      if error then break end
    end
    thumb = nil
  end
end

local function deflick(context)
  LrDialogs.attachErrorDialogToFunctionContext(context)
  local progress = LrProgressScope { title="Deflick", functionContext = context }
  local cat = LrApplication.activeCatalog();
  local selection = cat:getTargetPhotos();
  local count = #selection
  local max_iterations = 10
  assert(count > 2, "Not enough photos selected")
  
  analyze(selection[1])
  local startMedian = selection[1].deflickMedian
  analyze(selection[#selection])
  local endMedian = selection[#selection].deflickMedian
  
  for iteration = 1, max_iterations, 1 do
    print("Iteration: "..tostring(iteration))
    local moreIterationsNeeded = false
    for i,photo in ipairs(selection) do
      if i ~= 1 and i ~= count and photo.done ~= true then
        analyze(photo)
        progress:setPortionComplete(count * 2 * (iteration - 1) + i, count * 2 * max_iterations)
      end
    end
    print("Applying exposure corrections...")
    for i,photo in ipairs(selection) do
      if i ~= 1 and i ~= count then
        local offset = photo:getDevelopSettings().Exposure
        if offset == nil then offset = 0 end
        photo.offset = offset
      end
    end
    LrApplicationView.switchToModule("develop")
    for i,photo in ipairs(selection) do
      if i ~= 1 and i ~= count and photo.done ~= true then
        local target = startMedian + (endMedian - startMedian) * (i / count)
        if math.abs(target - photo.deflickMedian) > deflickerThreshold then
          moreIterationsNeeded = true
          cat:setSelectedPhotos(photo,{})
          LrTasks.sleep(0.2)
          local offset = LrDevelopController.getValue("Exposure")
          if offset == nil then offset = 0 end
          local target = startMedian + (endMedian - startMedian) * (i / count)
          local ev = convertToEV(target) - convertToEV(photo.deflickMedian) + offset
          print(photo:getFormattedMetadata("fileName").." Exposure (ev): "..tostring(offset).." -> "..tostring(ev))
          LrDevelopController.setValue("Exposure", ev)
          progress:setPortionComplete(count * 2 * (iteration - 1) + count + i, count * 2 * max_iterations)
        else
          photo.done = true
        end
      end
    end
    LrApplicationView.switchToModule("library")
    --restore selection
    cat:setSelectedPhotos(selection[1],selection)
    if moreIterationsNeeded == false then break end
  end
  progress:done()
  print("deflick finished")
end

LrFunctionContext.postAsyncTaskWithContext("deflick", deflick)


