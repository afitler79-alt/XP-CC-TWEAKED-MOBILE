-- XP Pocket Mobile: instalador autocontenido para Pastebin.
-- No requiere HTTP ni descarga modulos externos.
local FILES = {
  ['startup.lua'] = [[local function drawCentered(y, text, foreground)
  local width, height = term.getSize()
  if y < 1 or y > height then return end
  text = tostring(text)
  if #text > width then text = text:sub(1, width) end
  term.setCursorPos(math.max(1, math.floor((width - #text) / 2) + 1), y)
  term.setTextColor(foreground or colors.white)
  term.setBackgroundColor(colors.black)
  term.write(text)
end

local function drawFlag(y)
  local width = term.getSize()
  local flagColors = {
    { colors.red, colors.red, colors.lime },
    { colors.red, colors.red, colors.lime },
    { colors.blue, colors.blue, colors.yellow },
  }
  for row = 1, 3 do
    local offset = 3 - row
    local x = math.floor((width - 6) / 2) + 1 + offset
    for column = 1, 3 do
      if x >= 1 and x + 1 <= width then
        term.setCursorPos(x, y + row - 1)
        term.setBackgroundColor(flagColors[row][column])
        term.write("  ")
      end
      x = x + 2
    end
  end
  term.setBackgroundColor(colors.black)
end

local function startupAnimation()
  local width, height = term.getSize()
  local top = math.max(1, math.floor((height - 12) / 2) + 1)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()

  drawFlag(top)
  drawCentered(top + 4, "Microsoft", colors.lightGray)
  drawCentered(top + 5, "Windows XP", colors.white)
  drawCentered(top + 6, "Professional", colors.lightGray)

  local barWidth = math.min(20, math.max(4, width - 4))
  local barX = math.max(1, math.floor((width - barWidth) / 2) + 1)
  local barY = top + 9
  local innerWidth = math.max(1, barWidth - 2)
  for frame = 0, 17 do
    if barY >= 1 and barY <= height and barX + barWidth - 1 <= width then
      term.setCursorPos(barX, barY)
      term.setTextColor(colors.gray)
      term.setBackgroundColor(colors.black)
      term.write("[" .. string.rep(" ", innerWidth) .. "]")

      local blockWidth = math.min(3, innerWidth)
      local travel = math.max(0, innerWidth - blockWidth)
      local blockX = barX + 1 + (frame % (travel + 1))
      term.setCursorPos(blockX, barY)
      term.setBackgroundColor(colors.blue)
      term.write(string.rep(" ", blockWidth))
    end
    drawCentered(top + 11, "Iniciando...", colors.gray)
    sleep(0.1)
  end

  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)

local ok, err = pcall(function()
  startupAnimation()
  require("sys.mobile.boot").run()
end)

if not ok then
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.red)
  term.clear()
  term.setCursorPos(1, 1)
  print("XP Pocket Mobile: error de inicio")
  print(tostring(err))
  print("")
  print("Comprueba que /sys/mobile y /apps")
  print("estén instalados. Pulsa una tecla.")
  os.pullEvent("key")
end
]],
  ['sys/mobile/boot.lua'] = [[local ui = require("sys.mobile.ui")
local sensors = require("sys.mobile.sensors")
local sound = require("sys.mobile.sound")
local unpackValues = table.unpack or unpack

local M = {}
local SETTINGS = "/sys/mobile/settings"

local function loadSettings()
  local defaults = {
    playerRange = 32,
    createPeripheral = "",
    createOutputs = { clutch = "back", gearbox = "left", sequencer = "right" },
    createOutputMode = "redstone",
    clickSounds = true,
    bookmarks = {
      { "Wikipedia", "https://en.wikipedia.org" },
      { "DuckDuckGo", "https://lite.duckduckgo.com/lite/" },
      { "BBC News", "https://feeds.bbci.co.uk/news/rss.xml" },
    },
  }
  if fs.exists(SETTINGS) then
    local file = fs.open(SETTINGS, "r")
    local raw = file and file.readAll()
    if file then file.close() end
    local ok, loaded = pcall(textutils.unserialize, raw or "")
    if ok and type(loaded) == "table" then
      for key, value in pairs(loaded) do defaults[key] = value end
    end
  end
  return defaults
end

local function saveSettings(settings)
  local file, err = fs.open(SETTINGS, "w")
  if not file then return nil, err end
  file.write(textutils.serialize(settings))
  file.close()
  return true
end

local function startApp(name, ctx)
  local ok, app = pcall(require, "apps." .. name)
  if not ok then
    ctx.notify("No se pudo abrir " .. name .. ": " .. tostring(app))
    return
  end
  ctx.app = app
  ctx.appName = name
  if app.open then
    local good, err = pcall(app.open, ctx)
    if not good then ctx.notify(tostring(err)) end
  end
  if ctx.playSound then ctx.playSound("action") end
end

local function toggleSplit(ctx)
  if ctx.split then
    if ctx.splitApp and ctx.splitApp.close then pcall(ctx.splitApp.close, ctx) end
    ctx.split, ctx.splitApp = false, nil
    if ctx.playSound then ctx.playSound("action") end
    return
  end
  if not ctx.app then
    ctx.notify("Abre una aplicacion antes de activar Split.")
    return
  end
  local _, height = term.getSize()
  if not window or height < 18 then
    ctx.notify("Split requiere API window y al menos 18 filas.")
    return
  end
  local moduleName = ctx.appName == "radar" and "home" or "radar"
  local ok, app = pcall(require, "apps." .. moduleName)
  if not ok then ctx.notify("No se pudo abrir panel dividido: " .. tostring(app)); return end
  ctx.splitApp, ctx.split = app, true
  if app.open then
    local opened, err = pcall(app.open, ctx)
    if not opened then ctx.notify("Split: " .. tostring(err)) end
  end
  if ctx.playSound then ctx.playSound("action") end
end

local function closeApp(ctx)
  if ctx.app and ctx.app.close then pcall(ctx.app.close, ctx) end
  if ctx.splitApp and ctx.splitApp.close then pcall(ctx.splitApp.close, ctx) end
  ctx.app, ctx.appName, ctx.split, ctx.splitApp = nil, nil, false, nil
end

local function drawShutdownAnimation()
  local width, height = term.getSize()
  local centerY = math.max(1, math.floor(height / 2))
  local barWidth = math.min(20, math.max(1, width - 4))
  local barX = math.max(1, math.floor((width - barWidth) / 2) + 1)
  local barY = math.min(height, centerY + 2)
  local innerWidth = math.max(1, barWidth - 2)

  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  for frame = 0, 11 do
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    ui.center(math.max(1, centerY - 2), "Windows XP Pocket", colors.white, colors.black)
    ui.center(centerY, "Apagando...", colors.lightGray, colors.black)

    if barWidth >= 3 and barX + barWidth - 1 <= width then
      term.setCursorPos(barX, barY)
      term.setTextColor(colors.gray)
      term.write("[" .. string.rep(" ", innerWidth) .. "]")

      local remaining = math.max(0, innerWidth - math.floor(frame * innerWidth / 11))
      if remaining > 0 then
        term.setCursorPos(barX + 1, barY)
        term.setBackgroundColor(colors.blue)
        term.write(string.rep(" ", remaining))
      end
    end
    sleep(0.08)
  end

  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.lightGray)
  term.clear()
  ui.center(centerY, "Ya puedes apagar el equipo.", colors.lightGray, colors.black)
  sleep(0.35)
  term.setBackgroundColor(colors.black)
  term.clear()
end

local function shutdown(ctx)
  closeApp(ctx)
  sound.play("shutdown", ctx.settings.clickSounds)
  drawShutdownAnimation()
  os.shutdown()
end

local function resumeJobs(ctx, event)
  for i = #ctx.jobs, 1, -1 do
    local job = ctx.jobs[i]
    local matches = job.waitFor == nil or event[1] == "timer" or (event[1] == job.waitFor
      and (job.target == nil or event[2] == job.target))
    if matches then
      local ok, waitFor, target = coroutine.resume(job.thread)
      if not ok then
        table.remove(ctx.jobs, i)
        if job.onError then pcall(job.onError, waitFor) end
        ctx.notify("Tarea en segundo plano: " .. tostring(waitFor))
      elseif coroutine.status(job.thread) == "dead" then
        table.remove(ctx.jobs, i)
      else
        job.waitFor, job.target = waitFor, target
      end
    end
  end
end

local function drawHome(ctx)
  local home = require("apps.home")
  home.draw(ctx)
end

local function render(ctx)
  local parent = term.current()
  local w, h = term.getSize()
  term.setBackgroundColor(colors.white)
  term.setTextColor(colors.black)
  term.clear()
  local canSplit = ctx.split and ctx.splitApp and window and h >= 18
  if canSplit then
    local paneHeight = math.floor((h - 2) / 2)
    local topOk, top = pcall(window.create, parent, 1, 1, w, paneHeight + 1, true)
    local bottomOk, bottom = pcall(window.create, parent, 1, paneHeight + 1, w, h - paneHeight, true)
    if topOk and bottomOk then
      term.redirect(top)
      ui.title(ctx, ctx.app, 2)
      local firstOk, firstErr = pcall(ctx.app.draw, ctx)
      if not firstOk then ctx.notify("Split: " .. tostring(firstErr)) end
      term.redirect(bottom)
      ui.title(ctx, ctx.splitApp, 2)
      local secondOk, secondErr = pcall(ctx.splitApp.draw, ctx)
      if not secondOk then ctx.notify("Split: " .. tostring(secondErr)) end
      term.redirect(parent)
    else
      term.redirect(parent)
      ctx.notify("No se pudieron crear las ventanas divididas.")
    end
  elseif ctx.app then
    ui.status(ctx)
    ui.title(ctx, ctx.app)
    local ok, err = pcall(ctx.app.draw, ctx)
    if not ok then
      ui.text(2, 4, "Error de aplicación:", colors.red, colors.white)
      ui.text(2, 5, tostring(err), colors.red, colors.white, term.getSize())
    end
  else
    ui.status(ctx)
    drawHome(ctx)
  end
  if ctx.menu then
    local w, h = term.getSize()
    local x, y = 1, math.max(2, h - 8)
    local panelWidth = math.min(w, 28)
    local columnWidth = math.max(1, math.floor(panelWidth / 2))
    ui.fill(x, y, panelWidth, 8, colors.lightGray)
    ui.fill(x, y, panelWidth, 1, colors.blue)
    ui.text(x + 1, y, "Programas", colors.white, colors.blue, panelWidth - 2)
    if x + panelWidth <= w then
      ui.fill(x + panelWidth, y + 1, 1, 7, colors.gray)
    end
    if y + 8 < h then
      ui.fill(x + 1, y + 8, panelWidth, 1, colors.gray)
    end
    local pages = {
      {
        { "IE Mobile", "Radar", "Messenger", "Create", "GPS" },
        { "Archivos", "Ajustes", "Pocket CMD", "Geo Scanner", "Split", "Mapa" },
      },
      {
        { "Calculadora", "Notas", "Reloj", "Redstone", "Inventario" },
        { "Media", "Inicio", "Apagar", "YouTube", "" },
      },
    }
    local entries = pages[ctx.menuPage or 1]
    for row = 1, 6 do
      local rowY = y + row
      for column = 1, 2 do
        local label = entries[column][row]
        if label and label ~= "" then
          local cellX = x + (column - 1) * columnWidth
          local color = row % 2 == 0 and colors.white or colors.lightGray
          ui.fill(cellX, rowY, math.min(columnWidth, panelWidth - (column - 1) * columnWidth), 1, color)
          ui.text(cellX + 1, rowY, label, colors.blue, color, math.max(1, columnWidth - 2))
        end
      end
    end
    local footerY = y + 7
    ui.text(x + 1, footerY, ctx.menuPage == 2 and "< Apps 2/2" or "Apps 1/2 >",
      colors.blue, colors.lightGray, panelWidth - 2)
  end
  term.redirect(parent)
  ui.status(ctx)
  ui.dock(ctx)
end

local function isTouch(event, x, y, ctx)
  local w, h = term.getSize()
  local slot = math.max(1, math.floor(w / 4))
  if ctx.menu then
    if y == h and x <= slot then
      ctx.menu = false
      return true
    end
    local menuTop = math.max(2, h - 8)
    if x >= 1 and x <= math.min(w, 28) and y == menuTop + 7 then
      ctx.menuPage = ctx.menuPage == 2 and 1 or 2
      return true
    end
    if x >= 1 and x <= math.min(w, 28) and y > menuTop and y <= menuTop + 6 then
      local columnWidth = math.max(1, math.floor(math.min(w, 28) / 2))
      local column = x > columnWidth and 2 or 1
      local row = y - menuTop
      local pages = {
        {
          { "ie", "radar", "messenger", "create", "gps" },
          { "explorer", "settings", "cmd", "ores", "split", "map" },
        },
        {
          { "calculator", "notes", "clock", "redstone", "inventory" },
          { "media", "home", "shutdown", "youtube", "" },
        },
      }
      local action = pages[ctx.menuPage or 1][column][row]
      ctx.menu = false
      if action == "split" then
        toggleSplit(ctx)
      elseif action and action ~= "" and action ~= "home" and action ~= "shutdown" then
        startApp(action, ctx)
      elseif action == "home" then
        closeApp(ctx)
      elseif action == "shutdown" then
        shutdown(ctx)
      end
      return true
    end
    ctx.menu = false
  end
  if y == h then
    if x <= slot then
      ctx.menu = not ctx.menu
      return true
    end
    if ctx.app then
      if x <= slot * 2 then
        if ctx.app.back then pcall(ctx.app.back, ctx) else closeApp(ctx) end
        return true
      end
      if x <= slot * 3 then ctx.menu = not ctx.menu; return true end
      closeApp(ctx)
      return true
    end
  end
  if ctx.app and y == 2 and x >= term.getSize() - 3 then
    closeApp(ctx)
    return true
  end
  if ctx.split and ctx.splitApp and y == math.floor((h - 2) / 2) + 2
    and x >= term.getSize() - 3 then
    toggleSplit(ctx)
    return true
  end
  if not ctx.app then
    local home = require("apps.home")
    home.touch(ctx, x, y, startApp)
    return true
  end
  local app, localY = ctx.app, y
  if ctx.split and ctx.splitApp and h >= 18 then
    local paneHeight = math.floor((h - 2) / 2)
    if y >= paneHeight + 2 then
      app, localY = ctx.splitApp, y - paneHeight
    elseif y < 2 or y > paneHeight + 1 then
      return true
    end
  end
  if app.touch then
    local ok, err
    if app == ctx.splitApp and app.title == "Inicio" then
      ok, err = pcall(app.touch, ctx, x, localY, startApp)
    else
      ok, err = pcall(app.touch, ctx, x, localY)
    end
    if not ok then ctx.notify("Error: " .. tostring(err)) end
  end
  return true
end

function M.run()
  if not term.isColor() then error("Se requiere una terminal a color") end
  local settings = loadSettings()
  sound.play("startup", settings.clickSounds)
  local ctx
  ctx = {
    settings = settings,
    app = nil,
    appName = nil,
    menu = false,
    notifications = {},
    jobs = {},
    world = sensors.world(),
    power = sensors.power(),
    spawn = function(fn, onError)
      local thread = coroutine.create(fn)
      local job = { thread = thread, onError = onError }
      ctx.jobs[#ctx.jobs + 1] = job
      local ok, waitFor, target = coroutine.resume(thread)
      if not ok then
        table.remove(ctx.jobs)
        if onError then pcall(onError, waitFor) end
        ctx.notify("Tarea en segundo plano: " .. tostring(waitFor))
      elseif coroutine.status(thread) == "dead" then
        table.remove(ctx.jobs)
      else
        job.waitFor, job.target = waitFor, target
      end
    end,
    notify = function(message)
      message = tostring(message)
      ctx.notifications[#ctx.notifications + 1] = message
      while #ctx.notifications > 8 do table.remove(ctx.notifications, 1) end
      if message:lower():find("overstress", 1, true) then
        local speaker = require("sys.mobile.peripherals").find("speaker")
        if speaker and speaker.playNote then pcall(speaker.playNote, "pling", 1, 12) end
      end
    end,
    saveSettings = function()
      local ok, err = saveSettings(settings)
      if not ok then error("No se guardó la configuración: " .. tostring(err)) end
    end,
    playSound = function(kind)
      return sound.play(kind, settings.clickSounds)
    end,
  }
  local tick = os.startTimer(1)
  local lastAlert = false
  local monitor
  if peripheral and peripheral.getNames and peripheral.wrap then
    for _, name in ipairs(peripheral.getNames()) do
      local typeOk, typeName = pcall(peripheral.getType, name)
      if typeOk and typeName == "monitor" then
        local ok, candidate = pcall(peripheral.wrap, name)
        if ok and candidate then
          local sizeOk, width, height = pcall(candidate.getSize)
          if sizeOk and width <= height then
            monitor = candidate
            break
          end
        end
      end
    end
  end
  if monitor then
    pcall(monitor.setTextScale, 0.5)
    term.redirect(monitor)
  end
  while true do
    render(ctx)
    local event = { os.pullEvent() }
    if event[1] == "monitor_touch" then
      event = { "mouse_click", 1, event[3], event[4] }
    end
    if event[1] == "timer" and event[2] == tick then
      ctx.world = sensors.world()
      ctx.power = sensors.power()
      if ctx.appName == "radar" and ctx.app.refresh then
        pcall(ctx.app.refresh, ctx)
      elseif ctx.appName == "create" and ctx.app.refresh then
        pcall(ctx.app.refresh, ctx)
      end
      if ctx.app and ctx.app.tick then
        local ticked, tickError = pcall(ctx.app.tick, ctx)
        if not ticked then ctx.notify("Error de app: " .. tostring(tickError)) end
      end
      local telemetry = sensors.createTelemetry(settings)
      if telemetry and telemetry.overstressed and not lastAlert then
        ctx.notify("Create Overstress: red detenida")
      end
      lastAlert = telemetry and telemetry.overstressed or false
      tick = os.startTimer(1)
    elseif event[1] == "mouse_click" then
      ctx.playSound("click")
      isTouch(event[2], event[3], event[4], ctx)
    elseif event[1] == "mouse_drag" and ctx.app and ctx.app.drag then
      pcall(ctx.app.drag, ctx, event[2], event[3], event[4])
    elseif event[1] == "chat" or event[1] == "chat_message" then
      local user, message = event[2], event[3]
      ctx.notify(tostring(user or "Servidor") .. ": " .. tostring(message or ""))
      if ctx.app and ctx.app.event then
        local ok, err = pcall(ctx.app.event, ctx, event[1], user, message)
        if not ok then ctx.notify("Error: " .. tostring(err)) end
      end
    elseif ctx.app and ctx.app.event then
      local ok, err = pcall(ctx.app.event, ctx, unpackValues(event))
      if not ok then ctx.notify("Error: " .. tostring(err)) end
    end
    resumeJobs(ctx, event)
  end
end

return M
]],
  ['sys/mobile/ui.lua'] = [[local M = {}
local C = colors

M.colors = {
  blue = C.blue, title = C.lightBlue, navy = C.blue,
  light = C.white, panel = C.lightBlue, text = C.black,
  green = C.lime, gray = C.gray, red = C.red,
}

M.theme = {
  sky = C.lightBlue,
  deepBlue = C.blue,
  paleBlue = C.cyan,
  grass = C.green,
  leaf = C.lime,
  panel = C.white,
  tile = C.lightGray,
  ink = C.black,
  muted = C.gray,
}

function M.size()
  return term.getSize()
end

function M.fill(x, y, width, height, color, char)
  local w, h = term.getSize()
  local line = string.rep(char or " ", math.max(0, math.min(width, w)))
  term.setBackgroundColor(color or C.black)
  for row = math.max(1, y), math.min(h, y + height - 1) do
    term.setCursorPos(math.max(1, x), row)
    term.write(line:sub(1, math.max(0, w - x + 1)))
  end
end

function M.text(x, y, value, fg, bg, maxWidth)
  local w, h = term.getSize()
  if y < 1 or y > h or x > w then return end
  value = tostring(value or "")
  if maxWidth then value = value:sub(1, maxWidth) end
  value = value:sub(1, math.max(0, w - x + 1))
  term.setCursorPos(math.max(1, x), y)
  if fg then term.setTextColor(fg) end
  if bg then term.setBackgroundColor(bg) end
  term.write(value)
end

function M.center(y, value, fg, bg)
  local w = term.getSize()
  value = tostring(value or "")
  M.text(math.max(1, math.floor((w - #value) / 2) + 1), y, value, fg, bg)
end

function M.button(x, y, width, label, bg, fg)
  local w = term.getSize()
  width = math.max(0, math.min(width, w - x + 1))
  if width == 0 then return { x = x, y = y, width = 0, height = 1 } end
  label = tostring(label)
  M.fill(x, y, width, 1, bg or C.blue)
  local caption = label:sub(1, width)
  local left = x + math.max(0, math.floor((width - #caption) / 2))
  M.text(left, y, caption, fg or C.white, bg or C.blue, width)
  return { x = x, y = y, width = width, height = 1 }
end

function M.hit(rect, x, y)
  return rect and x >= rect.x and x < rect.x + rect.width
    and y >= rect.y and y < rect.y + rect.height
end

function M.wrap(value, width)
  local lines = {}
  width = math.max(1, width)
  for paragraph in (tostring(value or "") .. "\n"):gmatch("(.-)\n") do
    paragraph = paragraph:gsub("%s+", " ")
    if paragraph == "" then
      lines[#lines + 1] = ""
    else
      while #paragraph > width do
        local cut = paragraph:sub(1, width):match("^.*()%s")
        if not cut or cut < 2 then cut = width end
        lines[#lines + 1] = paragraph:sub(1, cut):gsub("%s+$", "")
        paragraph = paragraph:sub(cut + 1):gsub("^%s+", "")
      end
      lines[#lines + 1] = paragraph
    end
  end
  return lines
end

function M.status(ctx)
  local w = term.getSize()
  M.fill(1, 1, w, 1, C.blue)
  local signal = http and http.get and "W" or "X"
  local power = ctx.power or "--"
  local time = os.date("%H:%M")
  local notice = #ctx.notifications > 0 and "!" or " "
  M.text(1, 1, " Start", C.white, C.blue, math.min(7, w))
  local indicators = signal .. " " .. power .. " " .. notice .. " " .. time
  M.text(math.max(1, w - #indicators + 1), 1, indicators, C.white, C.blue, #indicators)
end

function M.title(ctx, app, row)
  local w = term.getSize()
  row = row or 2
  M.fill(1, row, w, 1, C.blue)
  M.text(2, row, app.title or app.name or "Aplicacion", C.white, C.blue, math.max(1, w - 6))
  M.fill(math.max(1, w - 2), row, math.min(3, w), 1, C.red)
  M.text(w - 1, row, "X", C.white, C.red, 1)
end

function M.dock(ctx)
  local w, h = term.getSize()
  local slot = math.max(1, math.floor(w / 4))
  M.fill(1, h, w, 1, C.blue)
  M.button(1, h, slot, w < 32 and "Start" or "Inicio", C.green, C.black)
  if ctx.app then
    local backLabel = w < 32 and "<" or "Atras"
    local menuLabel = w < 32 and "Menu" or "Menu"
    local closeLabel = w < 32 and "X" or "Cerrar"
    M.button(slot + 1, h, slot, backLabel, C.lightBlue, C.white)
    M.button(slot * 2 + 1, h, slot, menuLabel, C.lightBlue, C.white)
    M.button(slot * 3 + 1, h, w - slot * 3, closeLabel, C.lightBlue, C.white)
  end
end

return M
]],
  ['sys/mobile/lib.lua'] = [[local ui = require("sys.mobile.ui")
local M = { ui = ui }

function M.label(ctx, x, y, text, width)
  ui.text(x, y, text, colors.black, colors.white, width)
end

function M.heading(ctx, y, title)
  local w = term.getSize()
  ui.fill(1, y, w, 1, colors.lightBlue)
  ui.text(2, y, title, colors.white, colors.lightBlue, w - 2)
end

function M.notification(ctx, message)
  ctx.notify(message)
end

function M.prompt(ctx, caption, initial)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  local _, height = term.getSize()
  term.setCursorPos(1, math.max(1, height - 1))
  term.clearLine()
  write(caption .. " ")
  return read(nil, nil, nil, initial or "")
end

function M.readFile(path, limit)
  if not fs.exists(path) or fs.isDir(path) then return nil, "No se puede leer el archivo" end
  local handle, err = fs.open(path, "r")
  if not handle then return nil, err end
  local data = handle.read(limit or 32768)
  handle.close()
  return data or ""
end

function M.writeFile(path, data)
  local parent = fs.getDir(path)
  if parent ~= "" and not fs.exists(parent) then fs.makeDir(parent) end
  local handle, err = fs.open(path, "w")
  if not handle then return nil, err end
  handle.write(data)
  handle.close()
  return true
end

return M
]],
  ['sys/mobile/peripherals.lua'] = [[local M = {}

local function invoke(device, method, ...)
  if not device or type(device[method]) ~= "function" then
    return nil
  end
  local ok, value = pcall(device[method], ...)
  if ok then return value end
  return nil
end

function M.find(typeName)
  if not peripheral or not peripheral.find then return nil end
  local ok, device = pcall(peripheral.find, typeName)
  if ok then return device end
  return nil
end

function M.method(device, names, ...)
  for _, name in ipairs(names) do
    local value = invoke(device, name, ...)
    if value ~= nil then return value, name end
  end
  return nil
end

function M.describe(device)
  local result = {}
  if not device then return result end
  local ok, methods = pcall(peripheral.getMethods, peripheral.getName(device))
  if ok and type(methods) == "table" then
    for _, name in ipairs(methods) do result[name] = true end
  end
  return result
end

function M.names()
  if not peripheral or not peripheral.getNames then return {} end
  local ok, names = pcall(peripheral.getNames)
  if ok and type(names) == "table" then return names end
  return {}
end

return M
]],
  ['sys/mobile/sensors.lua'] = [[local devices = require("sys.mobile.peripherals")
local M = {}

local function text(value)
  if value == nil then return nil end
  if type(value) == "table" then return text(value.name or value.biome or value.weather or value.value) end
  return tostring(value)
end

function M.world()
  local environment = devices.find("environmentDetector")
  local weather = devices.find("weatherDetector")
  local info = {
    biome = devices.method(environment, { "getBiome" }),
    dimension = devices.method(environment, { "getDimension" }),
    moon = devices.method(environment, { "getMoonId", "getMoonPhase" }),
    worldTime = devices.method(environment, { "getTime", "getWorldTime", "getDay" }),
    weather = devices.method(weather, { "getWeather" }),
  }
  for key, value in pairs(info) do info[key] = text(value) or "--" end
  for _, key in ipairs({ "biome", "dimension", "moon", "worldTime", "weather" }) do
    if info[key] == nil then info[key] = "--" end
  end
  return info
end

function M.players(range)
  local detector = devices.find("playerDetector")
  if not detector then return nil, "Player Detector no conectado" end
  local names = devices.method(detector, { "getPlayersInRange", "getPlayers" }, range or 32)
  if type(names) ~= "table" then return nil, "El detector no devolvió jugadores" end
  local result = {}
  for _, entry in ipairs(names) do
    local name = type(entry) == "table" and (entry.name or entry.username) or entry
    if type(name) == "string" then
      local position = devices.method(detector, { "getPlayerPos", "getPlayerPosition" }, name)
      if type(position) ~= "table" and type(entry) == "table" then position = entry end
      if type(position) ~= "table" then position = {} end
      local x, y, z = position.x or "?", position.y or "?", position.z or "?"
      local distance = position.distance or "?"
      result[#result + 1] = {
        name = name,
        x = x, y = y, z = z, distance = distance,
      }
    end
  end
  return result
end

function M.createTelemetry(config)
  local configured = config.createPeripheral
  local device
  if configured and configured ~= "" and peripheral then
    local ok, value = pcall(peripheral.wrap, configured)
    if ok then device = value end
  end
  if not device then
    for _, name in ipairs(devices.names()) do
      local ok, candidate = pcall(peripheral.wrap, name)
      if ok and candidate then
        local methods = devices.describe(candidate)
        if methods.getSpeed or methods.getStress or methods.getStressCapacity then
          device = candidate
          break
        end
      end
    end
  end
  if not device then return nil, "No se detectó un puente/periférico de Create" end
  local rpm = devices.method(device, { "getSpeed", "getRPM", "getRotationSpeed" })
  local stress = devices.method(device, { "getStress", "getStressImpact" })
  local capacity = devices.method(device, { "getStressCapacity", "getCapacity" })
  local stalled = devices.method(device, { "isStalled", "getStalled" })
  local overstressed = devices.method(device, { "isOverstressed", "getOverstressed" })
  return {
    rpm = rpm or 0,
    stress = stress or 0,
    capacity = capacity,
    stalled = stalled == true,
    overstressed = overstressed == true,
  }
end

function M.power()
  local storage = devices.find("energyStorage")
  if storage then
    local energy = devices.method(storage, { "getEnergy", "getEnergyStored" })
    local capacity = devices.method(storage, { "getEnergyCapacity", "getMaxEnergy" })
    if type(energy) == "number" and type(capacity) == "number" and capacity > 0 then
      return math.floor(energy * 100 / capacity) .. "%"
    end
  end
  if redstone and redstone.getInput then
    for _, side in ipairs({ "left", "right", "top", "bottom", "front", "back" }) do
      if redstone.getInput(side) then return "R+" end
    end
    return "R-"
  end
  return "--"
end

return M
]],
  ['sys/mobile/sound.lua'] = [[local M = {}
local speaker

local function getSpeaker()
  if speaker then return speaker end
  if not peripheral or type(peripheral.find) ~= "function" then return nil end
  local ok, found = pcall(peripheral.find, "speaker")
  if ok then speaker = found end
  return speaker
end

function M.play(kind, enabled)
  if enabled == false then return false end
  local device = getSpeaker()
  if not device or type(device.playNote) ~= "function" then return false end

  local notes
  if kind == "action" then
    notes = {
      { "chime", 0.65, 17 },
      { "pling", 0.45, 21 },
    }
  elseif kind == "startup" then
    notes = {
      { "chime", 0.65, 12 },
      { "bell", 0.65, 16 },
      { "pling", 0.6, 19 },
      { "chime", 0.55, 21 },
      { "pling", 0.45, 24 },
    }
  elseif kind == "shutdown" then
    notes = {
      { "pling", 0.55, 22 },
      { "bell", 0.6, 19 },
      { "chime", 0.55, 16 },
      { "bell", 0.45, 12 },
      { "chime", 0.35, 9 },
    }
  else
    notes = { { "hat", 0.35, 18 } }
  end

  local played = false
  for index, note in ipairs(notes) do
    local ok = pcall(device.playNote, note[1], note[2], note[3])
    played = played or ok
    if index < #notes and (kind == "startup" or kind == "shutdown") then
      sleep(0.1)
    end
  end
  return played
end

return M
]],
  ['drivers/create.lua'] = [[local peripherals = require("sys.mobile.peripherals")
local M = {}
local KEYS = { "clutch", "gearbox", "sequencer" }

function M.readOutputs(settings)
  local result = {}
  local integrator
  if settings.createOutputMode == "integrator" then
    integrator = peripherals.find("redstoneIntegrator")
  end
  for _, key in ipairs(KEYS) do
    local side = settings.createOutputs and settings.createOutputs[key]
    local value
    if side and integrator and type(integrator.getOutput) == "function" then
      local ok, output = pcall(integrator.getOutput, side)
      if ok then value = output end
    elseif side and redstone and redstone.getOutput then
      local ok, output = pcall(redstone.getOutput, side)
      if ok then value = output end
    end
    result[key] = value == true
  end
  return result
end

function M.setOutput(settings, key, value)
  local side = settings.createOutputs and settings.createOutputs[key]
  if not side or side == "" then error("Configura una salida para " .. key) end
  if settings.createOutputMode == "integrator" then
    local device = peripherals.find("redstoneIntegrator")
    if not device or type(device.setOutput) ~= "function" then
      error("Redstone Integrator no conectado")
    end
    device.setOutput(side, value)
  else
    if not redstone or not redstone.setOutput then error("API de redstone no disponible") end
    redstone.setOutput(side, value)
  end
end

return M
]],
  ['apps/home.lua'] = [[local ui = require("sys.mobile.ui")
local M = { title = "Inicio" }

local apps = {
  { "Mi PC", "explorer", "PC" },
  { "Internet", "ie", "IE" },
  { "Create", "create", "CR" },
  { "Sensores", "radar", "AP" },
  { "Media", "media", "WMP" },
  { "Ajustes", "settings", "XP" },
  { "Messenger", "messenger", "MSN" },
  { "Pocket CMD", "cmd", ">" },
  { "GPS", "gps", "GPS" },
  { "Ores", "ores", "ORE" },
  { "Calculadora", "calculator", "CALC" },
  { "Notas", "notes", "TXT" },
  { "Reloj", "clock", "TIME" },
  { "Redstone", "redstone", "RS" },
  { "Inventario", "inventory", "INV" },
  { "YouTube", "youtube", "YT" },
  { "Mapa", "map", "MAP" },
}

local iconColors = {
  colors.blue, colors.blue, colors.orange, colors.cyan,
  colors.purple, colors.green, colors.red, colors.gray,
  colors.blue, colors.orange, colors.purple, colors.gray, colors.blue,
  colors.red, colors.orange, colors.red, colors.green,
}

local page = 1

local function compact(text, width)
  text = tostring(text or "")
  if #text > width then return text:sub(1, math.max(1, width - 1)) .. "~" end
  return text
end

local function centered(x, y, width, value, fg, bg)
  value = compact(value, width)
  local left = x + math.max(0, math.floor((width - #value) / 2))
  ui.text(left, y, value, fg, bg, width)
end

local function dimensionName(world)
  local dimension = tostring(world.dimension or "--")
  local names = {
    ["minecraft:overworld"] = "Overworld",
    ["minecraft:the_nether"] = "Nether",
    ["minecraft:the_end"] = "The End",
  }
  return names[dimension] or dimension
end

local function weatherLine(world, width)
  local place = tostring(world.biome or "--")
  local weather = tostring(world.weather or "--")
  return compact(place .. " / " .. weather, width)
end

function M.draw(ctx)
  local w, h = term.getSize()
  local world = ctx.world or {}

  ui.fill(1, 2, w, math.max(1, h - 2), colors.white)
  ui.fill(1, 2, w, 1, colors.lightBlue)
  ui.text(2, 2, "Pocket PC", colors.white, colors.lightBlue)
  ui.text(math.max(1, w - 12), 2, "Luna Mobile", colors.white, colors.lightBlue, 13)

  ui.fill(2, 3, math.max(1, w - 2), 4, colors.cyan)
  ui.fill(2, 3, math.max(1, w - 2), 1, colors.blue)
  ui.text(3, 3, "MI MUNDO", colors.white, colors.blue)
  ui.text(3, 4, compact("Dimension: " .. dimensionName(world), w - 4),
    colors.white, colors.cyan, w - 4)
  ui.text(3, 5, weatherLine(world, w - 4), colors.white, colors.cyan, w - 4)
  local moonTime = "Luna " .. tostring(world.moon or "--") .. "  |  " .. tostring(world.worldTime or "--")
  ui.text(3, 6, compact(moonTime, w - 4), colors.white, colors.cyan, w - 4)

  ui.fill(1, 7, w, 1, colors.green)
  ui.text(2, 7, os.date("%A, %d %B"), colors.white, colors.green, w - 2)
  ui.text(math.max(1, w - 7), 7, "XP", colors.white, colors.green, 2)

  local columns = w < 22 and 2 or 3
  local cell = math.max(1, math.floor((w - 2) / columns))
  local perPage = columns * 3
  local pages = math.max(1, math.ceil(#apps / perPage))
  page = math.min(page, pages)
  local first = (page - 1) * perPage + 1
  local last = math.min(#apps, first + perPage - 1)
  for i = first, last do
    local entry = apps[i]
    local localIndex = i - first
    local column = localIndex % columns
    local row = math.floor(localIndex / columns)
    local x = 2 + column * cell
    local y = 8 + row * 3
    if y < h - 2 then
      local tileWidth = math.max(1, math.min(cell - 1, w - x + 1))
      ui.fill(x, y, tileWidth, 2, colors.lightGray)
      ui.fill(x, y, tileWidth, 1, iconColors[i])
      centered(x, y, tileWidth, "[" .. entry[3] .. "]", colors.white, iconColors[i])
      centered(x, y + 1, tileWidth, entry[1], colors.black, colors.lightGray)
    end
  end

  if pages > 1 and h >= 12 then
    ui.fill(1, h - 2, w, 1, colors.lightBlue)
    ui.text(2, h - 2, "<", colors.white, colors.blue, 1)
    ui.text(math.max(1, math.floor((w - 5) / 2)), h - 2,
      "Apps " .. page .. "/" .. pages, colors.white, colors.lightBlue, 12)
    ui.text(w, h - 2, ">", colors.white, colors.blue, 1)
  elseif #ctx.notifications > 0 and h >= 12 then
    ui.fill(2, h - 2, math.max(1, w - 2), 1, colors.yellow)
    ui.text(3, h - 2, "!" .. compact(ctx.notifications[#ctx.notifications], w - 4),
      colors.black, colors.yellow, w - 4)
  end
end

function M.touch(ctx, x, y, startApp)
  local w = term.getSize()
  local _, h = term.getSize()
  local columns = w < 22 and 2 or 3
  local perPage = columns * 3
  local pages = math.max(1, math.ceil(#apps / perPage))
  if pages > 1 and y == h - 2 then
    if x <= 3 then page = page > 1 and page - 1 or pages
    elseif x >= w - 2 then page = page < pages and page + 1 or 1 end
    return
  end
  if y < 8 then return end
  local cell = math.max(1, math.floor((w - 2) / columns))
  local col = math.floor((x - 2) / cell)
  local row = math.floor((y - 8) / 3)
  if col < 0 or col >= columns or row < 0 or x > w - 1 then return end
  local index = (page - 1) * perPage + row * columns + col + 1
  if apps[index] and y <= h - 3 then
    startApp(apps[index][2], ctx)
  end
end

return M
]],
  ['apps/ie.lua'] = [[local ui = require("sys.mobile.ui")
local lib = require("sys.mobile.lib")

local M = { title = "Internet Explorer Mobile" }
local MAX_BYTES = 24000
local state = { url = "", lines = {}, scroll = 1, message = "Elige un marcador o escribe una dirección." }

local function cleanHtml(html)
  html = html:gsub("<[Ss][Cc][Rr][Ii][Pp][Tt][^>]*>.-</[Ss][Cc][Rr][Ii][Pp][Tt]%s*>", " ")
  html = html:gsub("<[Ss][Tt][Yy][Ll][Ee][^>]*>.-</[Ss][Tt][Yy][Ll][Ee]%s*>", " ")
  html = html:gsub("<[Hh][Rr][^>]*>", "\n----------------\n")
  html = html:gsub("<[Bb][Rr][^>]*>", "\n")
  html = html:gsub("</[Pp]%s*>", "\n\n")
  html = html:gsub("</[Dd][Ii][Vv]%s*>", "\n")
  html = html:gsub("<[Ll][Ii][^>]*>", "\n * ")
  html = html:gsub("<[^>]->", " ")
  html = html:gsub("&nbsp;", " "):gsub("&amp;", "&"):gsub("&lt;", "<")
  html = html:gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&#39;", "'")
  html = html:gsub("&#(%d+);", function(n) return string.char(tonumber(n) % 128) end)
  html = html:gsub("[%z\1-\8\11\12\14-\31\127]", " ")
  html = html:gsub("[ \t\r]+", " ")
  html = html:gsub(" *\n *", "\n")
  html = html:gsub("\n\n\n+", "\n\n")
  return html
end

local function showText(text, width)
  local result = {}
  for paragraph in (text .. "\n"):gmatch("(.-)\n") do
    local wrapped = ui.wrap(paragraph, width)
    for _, line in ipairs(wrapped) do
      if line ~= "" or #result == 0 or result[#result] ~= "" then
        result[#result + 1] = line
      end
    end
  end
  return result
end

local function browse(url)
  if not http or not http.get then
    state.message = "HTTP API desactivada en la configuración de CraftOS."
    state.lines = { state.message }
    return
  end
  if type(url) ~= "string" or not url:match("^https?://[%w%.%-]+") or url:find("%s") then
    state.message = "Dirección no válida. Usa http:// o https://"
    state.lines = { state.message }
    return
  end
  state.url, state.scroll = url, 1
  local ok, response, reason = pcall(http.get, url, { ["User-Agent"] = "XP-Pocket-Mobile/1.0" })
  if not ok or not response then
    state.message = "No se pudo abrir la página: " .. tostring(ok and reason or response)
    state.lines = { state.message }
    return
  end
  local chunks, size = {}, 0
  local readOk, readError = pcall(function()
    while size < MAX_BYTES do
      local piece = response.read(math.min(2048, MAX_BYTES - size))
      if not piece or piece == "" then break end
      chunks[#chunks + 1] = piece
      size = size + #piece
    end
  end)
  pcall(response.close)
  if not readOk then
    state.message = "Error leyendo la pagina: " .. tostring(readError)
    state.lines = { state.message }
    return
  end
  local body = cleanHtml(table.concat(chunks))
  if body == "" then body = "(La página no contiene texto legible.)" end
  state.lines = showText(body, math.max(12, term.getSize() - 4))
  state.message = "Descargado (" .. size .. " bytes; vista de texto)"
end

local function openAddress(ctx)
  local url = lib.prompt(ctx, "URL:", state.url)
  if url and url ~= "" then browse(url) end
end

function M.open()
  state.url, state.scroll = "", 1
  state.lines, state.message = {}, "Elige un marcador o escribe una direccion."
end

function M.draw(ctx)
  local w, h = term.getSize()
  ui.button(2, 3, math.min(w - 2, 14), "Direccion", colors.blue)
  ui.text(2, 4, state.url ~= "" and state.url or "Toca [Direccion]", colors.black, colors.white, w - 2)
  local bookmarks = ctx.settings.bookmarks or {}
  ui.text(2, 5, "Favoritos:", colors.blue, colors.white)
  for i = 1, math.min(3, #bookmarks) do
    ui.button(2 + (i - 1) * math.floor(math.max(1, w - 2) / 3), 6,
      math.floor(math.max(1, w - 2) / 3), bookmarks[i][1], colors.lightBlue)
  end
  ui.fill(1, 7, w, 1, colors.gray)
  ui.text(2, 7, state.message, colors.white, colors.gray, w - 2)
  for row = 9, h - 2 do
    local line = state.lines[state.scroll + row - 9]
    if line then ui.text(2, row, line, colors.black, colors.white, w - 2) end
  end
  ui.button(2, h - 1, 8, "Arriba", colors.blue)
  ui.button(11, h - 1, 8, "Abajo", colors.blue)
end

function M.touch(ctx, x, y)
  local w, h = term.getSize()
  if y == 3 or (y == 4 and x <= w) then
    openAddress(ctx)
  elseif y == 6 then
    local bookmarks = ctx.settings.bookmarks or {}
    local slot = math.floor((x - 2) / math.max(1, math.floor((w - 2) / 3))) + 1
    if bookmarks[slot] then browse(bookmarks[slot][2]) end
  elseif y == h - 1 then
    if x < 11 then state.scroll = math.max(1, state.scroll - 5)
    else state.scroll = math.min(math.max(1, #state.lines - (h - 10)), state.scroll + 5) end
  else
    state.scroll = math.max(1, math.min(#state.lines, state.scroll + (y > h / 2 and 2 or -2)))
  end
end

function M.drag(ctx, _, _, y)
  local _, h = term.getSize()
  state.scroll = math.max(1, math.min(#state.lines, state.scroll + (y > h / 2 and 2 or -2)))
end

return M
]],
  ['apps/radar.lua'] = [[local ui = require("sys.mobile.ui")
local sensors = require("sys.mobile.sensors")
local M = { title = "Sensor Hub / Radar" }
local state = { players = {}, error = nil, page = "players" }

local function refresh(ctx)
  local players, err = sensors.players(ctx.settings.playerRange)
  state.players, state.error = players or {}, err
end

function M.open(ctx)
  refresh(ctx)
end

function M.refresh(ctx)
  refresh(ctx)
end

function M.draw(ctx)
  local w, h = term.getSize()
  ui.button(2, 3, 12, "Actualizar", colors.blue)
  ui.button(16, 3, 10, "Ambiente", colors.lightBlue)
  if state.page == "world" then
    local world = ctx.world or {}
    ui.text(2, 5, "Bioma: " .. tostring(world.biome or "--"), colors.black, colors.white, w - 2)
    ui.text(2, 6, "Dimension: " .. tostring(world.dimension or "--"), colors.black, colors.white, w - 2)
    ui.text(2, 7, "Luna: " .. tostring(world.moon or "--") .. "  Hora: "
      .. tostring(world.worldTime or "--"), colors.black, colors.white, w - 2)
    ui.text(2, 8, "Clima: " .. tostring(world.weather or "--"), colors.black, colors.white, w - 2)
  else
    ui.text(2, 5, "Player Detector | rango " .. tostring(ctx.settings.playerRange) .. "m", colors.blue, colors.white, w - 2)
    if state.error then
      ui.text(2, 7, state.error, colors.red, colors.white, w - 2)
    elseif #state.players == 0 then
      ui.text(2, 7, "No hay jugadores en rango.", colors.gray, colors.white)
    else
      for i, player in ipairs(state.players) do
        local y = 7 + (i - 1) * 3
        if y < h - 1 then
          ui.fill(2, y, w - 3, 2, colors.lightGray)
          ui.text(3, y, player.name .. " (" .. tostring(player.distance) .. "m)", colors.blue, colors.lightGray, w - 4)
          ui.text(3, y + 1, "X:" .. tostring(player.x) .. " Y:" .. tostring(player.y) .. " Z:" .. tostring(player.z),
            colors.black, colors.lightGray, w - 4)
        end
      end
    end
  end
end

function M.touch(ctx, x, y)
  if y == 3 and x < 15 then refresh(ctx)
  elseif y == 3 and x >= 15 then state.page = state.page == "world" and "players" or "world" end
end

return M
]],
  ['apps/messenger.lua'] = [[local ui = require("sys.mobile.ui")
local lib = require("sys.mobile.lib")
local peripherals = require("sys.mobile.peripherals")
local M = { title = "MSN Messenger Mobile" }
local state = { log = {}, chatBox = nil }

local function add(message)
  state.log[#state.log + 1] = tostring(message)
  while #state.log > 20 do table.remove(state.log, 1) end
end

function M.open()
  state.chatBox = peripherals.find("chatBox")
end

function M.draw()
  local w, h = term.getSize()
  ui.text(2, 3, state.chatBox and "Conectado al Chat Box" or "Chat Box no conectado", 
    state.chatBox and colors.green or colors.red, colors.white, w - 2)
  ui.button(2, 5, 15, "Enviar mensaje", colors.blue)
  for i = math.max(1, #state.log - (h - 9)), #state.log do
    ui.text(2, 7 + i - math.max(1, #state.log - (h - 9)), state.log[i], colors.black, colors.white, w - 2)
  end
end

function M.touch(ctx, x, y)
  if y ~= 5 or x > 19 then return end
  if not state.chatBox then
    state.chatBox = peripherals.find("chatBox")
    if not state.chatBox then ctx.notify("Conecta un Chat Box de Advanced Peripherals."); return end
  end
  local message = lib.prompt(ctx, "Mensaje (vacio cancela):", "")
  if message and message ~= "" then
    local fn = state.chatBox.sendMessage
    if type(fn) ~= "function" then
      ctx.notify("Este Chat Box no ofrece sendMessage.")
    else
      local ok, err = pcall(fn, message, "Pocket XP", "[]")
      if ok then
        add("Yo: " .. message)
        ctx.notify("Mensaje enviado")
        if ctx.playSound then ctx.playSound("action") end
      else ctx.notify("Error de Chat Box: " .. tostring(err)) end
    end
  end
end

function M.event(ctx, event, user, message)
  if event == "chat" or event == "chat_message" then
    local line = tostring(user or "Servidor") .. ": " .. tostring(message or "")
    add(line)
  end
end

return M
]],
  ['apps/create.lua'] = [[local ui = require("sys.mobile.ui")
local sensors = require("sys.mobile.sensors")
local outputDriver = require("drivers.create")
local M = { title = "Create Controller Mobile" }
local state = { telemetry = nil, error = nil, outputs = { clutch = false, gearbox = false, sequencer = false } }
local keys = { "clutch", "gearbox", "sequencer" }

local function update(ctx)
  local telemetry, err = sensors.createTelemetry(ctx.settings)
  state.telemetry, state.error = telemetry, err
end

function M.refresh(ctx)
  update(ctx)
end

function M.open(ctx)
  state.outputs = outputDriver.readOutputs(ctx.settings)
  update(ctx)
end

function M.draw(ctx)
  local w, h = term.getSize()
  local t = state.telemetry
  ui.button(2, 3, 13, "Actualizar", colors.blue)
  if t then
    ui.text(2, 5, "RPM: " .. tostring(t.rpm), colors.black, colors.white, w - 2)
    ui.text(2, 6, "Stress: " .. tostring(t.stress) .. " / " .. tostring(t.capacity or "?"),
      colors.black, colors.white, w - 2)
    local health = t.overstressed and "OVERSTRESS" or (t.stalled and "STALLED" or "NORMAL")
    ui.text(2, 7, "Estado: " .. health, t.overstressed and colors.red or colors.green, colors.white, w - 2)
    if type(t.stress) == "number" and type(t.capacity) == "number" and t.capacity > 0 then
      local width = math.max(1, math.min(20, w - 4))
      local filled = math.max(0, math.min(width, math.floor(width * t.stress / t.capacity)))
      ui.text(2, 8, string.rep("#", filled) .. string.rep("-", width - filled),
        t.overstressed and colors.red or colors.green, colors.white, width)
    end
  else
    ui.text(2, 5, state.error or "Sin telemetria", colors.red, colors.white, w - 2)
  end
  ui.text(2, 9, "Salidas (redstone local o Integrator):", colors.blue, colors.white, w - 2)
  for i, key in ipairs(keys) do
    local y = 11 + (i - 1) * 2
    if y < h then
      ui.button(2, y, math.min(w - 3, 24), key .. ": " .. (state.outputs[key] and "ON" or "OFF"),
        state.outputs[key] and colors.green or colors.gray, colors.white)
    end
  end
end

function M.touch(ctx, x, y)
  if y == 3 then update(ctx); return end
  if y >= 11 and y <= 15 then
    local index = math.floor((y - 11) / 2) + 1
    local key = keys[index]
    if key then
      local nextValue = not state.outputs[key]
      local ok, err = pcall(outputDriver.setOutput, ctx.settings, key, nextValue)
      if ok then
        state.outputs[key] = nextValue
        if ctx.playSound then ctx.playSound("action") end
      else ctx.notify("Create: " .. tostring(err)) end
    end
  end
end

return M
]],
  ['apps/explorer.lua'] = [[local ui = require("sys.mobile.ui")
local lib = require("sys.mobile.lib")
local M = { title = "Mi PC - Explorador" }
local state = { path = "/", entries = {}, selected = nil, text = nil, lines = {}, error = nil }

local function refresh()
  if not fs.exists(state.path) or not fs.isDir(state.path) then state.path = "/" end
  state.entries = fs.list(state.path)
  table.sort(state.entries, function(a, b)
    local ad = fs.isDir(fs.combine(state.path, a))
    local bd = fs.isDir(fs.combine(state.path, b))
    if ad ~= bd then return ad end
    return a:lower() < b:lower()
  end)
  state.selected, state.text, state.lines, state.error = nil, nil, {}, nil
end

local function openEntry(ctx, entry)
  local path = fs.combine(state.path, entry)
  if fs.isDir(path) then
    state.path = path
    refresh()
  else
    state.selected = path
    local content, err = lib.readFile(path, 12000)
    state.text, state.error = content or "", err
    state.lines = {}
    for line in ((state.text or "") .. "\n"):gmatch("(.-)\n") do
      state.lines[#state.lines + 1] = line
    end
  end
end

function M.open()
  state.path = "/"
  refresh()
end

function M.draw(ctx)
  local w, h = term.getSize()
  ui.text(2, 3, state.path, colors.blue, colors.white, w - 2)
  ui.button(2, 4, 8, "Arriba", colors.blue)
  ui.button(12, 4, 9, "Actualizar", colors.lightBlue)
  if state.selected then
    local name = fs.getName(state.selected)
    ui.text(2, 6, name .. (state.error and " (error)" or ""), colors.blue, colors.white, w - 2)
    if state.error then
      ui.text(2, 7, tostring(state.error), colors.red, colors.white, w - 2)
    end
    for i = 1, math.min(5, math.max(0, h - 10)) do
      if state.lines[i] then ui.text(2, 6 + i + (state.error and 1 or 0), state.lines[i],
        colors.black, colors.white, w - 2) end
    end
    ui.button(2, h - 2, 9, "Editar", colors.green, colors.black)
    ui.button(13, h - 2, 9, "Cerrar", colors.gray)
  else
    for i, entry in ipairs(state.entries) do
      local y = 6 + i
      if y >= h - 2 then break end
      local path = fs.combine(state.path, entry)
      local prefix = fs.isDir(path) and "[+] " or "    "
      ui.text(2, y, prefix .. entry, fs.isDir(path) and colors.blue or colors.black, colors.white, w - 2)
    end
  end
end

function M.touch(ctx, x, y)
  local _, h = term.getSize()
  if y == 4 then
    if x <= 10 then state.path = fs.getDir(state.path); if state.path == "" then state.path = "/" end; refresh()
    else refresh() end
  elseif state.selected then
    if y == h - 2 and x < 12 then
      local current, lines = lib.readFile(state.selected, 12000)
      if not current then ctx.notify("No se pudo leer: " .. tostring(lines)); return end
      ui.fill(1, 3, term.getSize(), h - 4, colors.black)
      print("Editor XP - " .. fs.getName(state.selected))
      print("Escribe el texto por lineas; una linea con . guarda.")
      local replacement = {}
      while true do
        local line = read()
        if line == "." then break end
        replacement[#replacement + 1] = line
      end
      local ok, err = lib.writeFile(state.selected, table.concat(replacement, "\n") .. "\n")
      if ok then ctx.notify("Archivo guardado") else ctx.notify("Error: " .. tostring(err)) end
      refresh()
    elseif y == h - 2 then
      state.selected, state.text, state.lines = nil, nil, {}
    end
  elseif y >= 7 then
    local index = y - 6
    if state.entries[index] then openEntry(ctx, state.entries[index]) end
  end
end

return M
]],
  ['apps/media.lua'] = [[local ui = require("sys.mobile.ui")
local peripherals = require("sys.mobile.peripherals")
local M = { title = "Pocket Windows Media Player" }
local state = { tracks = {}, selected = 1, playing = false, stop = false, speaker = nil, message = "DFPWM en /music o /disk" }

local function scan()
  state.tracks = {}
  for _, directory in ipairs({ "/music", "/disk" }) do
    if fs.exists(directory) and fs.isDir(directory) then
      for _, name in ipairs(fs.list(directory)) do
        if not fs.isDir(fs.combine(directory, name)) and name:lower():match("%.dfpwm$") then
          state.tracks[#state.tracks + 1] = fs.combine(directory, name)
        end
      end
    end
  end
  if state.selected > #state.tracks then state.selected = math.max(1, #state.tracks) end
end

function M.open()
  scan()
end

function M.draw()
  local w, h = term.getSize()
  ui.fill(2, 3, w - 3, 2, colors.blue)
  ui.center(3, "Windows Media Player", colors.white, colors.blue)
  ui.button(2, 6, 7, "Play", colors.green, colors.black)
  ui.button(10, 6, 8, "Pause", colors.lightBlue)
  ui.button(20, 6, 7, "Stop", colors.red)
  ui.button(2, 8, 10, "Actualizar", colors.gray)
  ui.text(2, 10, state.message, colors.blue, colors.white, w - 2)
  for i, track in ipairs(state.tracks) do
    local y = 12 + i - 1
    if y >= h - 1 then break end
    ui.text(2, y, (i == state.selected and "> " or "  ") .. fs.getName(track),
      i == state.selected and colors.blue or colors.black, colors.white, w - 2)
  end
end

local function play(ctx)
  local path = state.tracks[state.selected]
  if not path then state.message = "No hay pistas .dfpwm"; return end
  if state.playing then state.message = "Ya hay una pista activa"; return end
  local speaker = peripherals.find("speaker")
  if not speaker then state.message = "Speaker no conectado"; return end
  local ok, decoderModule = pcall(require, "cc.audio.dfpwm")
  if not ok then state.message = "No está disponible cc.audio.dfpwm"; return end
  local input, err = fs.open(path, "rb")
  if not input then state.message = tostring(err); return end
  state.speaker, state.stop, state.playing = speaker, false, true
  state.message = "Reproduciendo: " .. fs.getName(path)
  local decoder = decoderModule.make_decoder()
  local speakerName
  if peripheral and peripheral.getName then
    local nameOk, name = pcall(peripheral.getName, speaker)
    if nameOk then speakerName = name end
  end
  local function playbackFailed(reason)
    pcall(input.close)
    state.playing = false
    state.message = "Error de audio: " .. tostring(reason)
  end
  ctx.spawn(function()
    while not state.stop do
      local compressed = input.read(8192)
      if not compressed then break end
      local audio = decoder(compressed)
      while not state.stop do
        local queued, accepted = pcall(speaker.playAudio, audio)
        if not queued then error(accepted) end
        if accepted then break end
        coroutine.yield("speaker_audio_empty", speakerName)
      end
    end
    input.close()
    state.playing = false
    state.message = "Reproducción terminada"
  end, playbackFailed)
end

function M.touch(ctx, x, y)
  if y == 6 and x < 9 then play(ctx)
  elseif y == 6 and x < 19 then
    state.stop = true
    if state.speaker and state.speaker.stop then pcall(state.speaker.stop) end
    state.message = "Pausado; Play reinicia la pista"
  elseif y == 6 then
    state.stop = true
    if state.speaker and state.speaker.stop then pcall(state.speaker.stop) end
    state.message = "Deteniendo..."
  elseif y == 8 then scan()
  elseif y >= 12 then
    local index = y - 11
    if state.tracks[index] then state.selected = index end
  end
end

return M
]],
  ['apps/cmd.lua'] = [[local ui = require("sys.mobile.ui")
local lib = require("sys.mobile.lib")
local M = { title = "Pocket CMD" }
local state = { history = { "Consola XP Pocket. Toca Ejecutar para introducir un comando." } }

function M.draw()
  local w, h = term.getSize()
  local clearX = w - 8
  if w >= 20 then
    ui.button(2, 3, clearX - 3, "Ejecutar", colors.blue)
    ui.button(clearX, 3, w - clearX, "Limpiar", colors.gray)
  else
    ui.button(2, 3, w - 2, "Ejecutar", colors.blue)
  end
  for i = math.max(1, #state.history - (h - 7)), #state.history do
    ui.text(2, 5 + i - math.max(1, #state.history - (h - 7)), state.history[i], colors.black, colors.white, w - 2)
  end
end

function M.touch(ctx, x, y)
  if y ~= 3 then return end
  local width = term.getSize()
  if width >= 20 and x >= width - 8 then state.history = {}; return end
  local command = lib.prompt(ctx, ">", "")
  if not command or command == "" then return end
  state.history[#state.history + 1] = "> " .. command
  local previous = term.current()
  local width, height = term.getSize()
  local output = window.create(previous, 1, 1, width, height, true)
  term.redirect(output)
  local ok, result = pcall(function()
    if shell and shell.execute then return shell.execute(command) end
    return shell.run(command)
  end)
  term.redirect(previous)
  for row = 1, height do
    local line = output.getLine(row)
    local text = type(line) == "table" and line[1] or line
    if text and text:match("%S") then state.history[#state.history + 1] = text:gsub("%s+$", "") end
  end
  if not ok then
    state.history[#state.history + 1] = "Error: " .. tostring(result)
  elseif result == false then
    state.history[#state.history + 1] = "Comando no encontrado o fallido."
  else
    state.history[#state.history + 1] = "Comando terminado."
  end
end

return M
]],
  ['apps/settings.lua'] = [[local ui = require("sys.mobile.ui")
local lib = require("sys.mobile.lib")
local M = { title = "Ajustes" }

function M.draw(ctx)
  local w = term.getSize()
  ui.text(2, 3, "Configuracion del sistema", colors.blue, colors.white, w - 2)
  ui.button(2, 5, 23, "Rango radar: " .. tostring(ctx.settings.playerRange) .. "m", colors.lightBlue)
  ui.button(2, 7, 23, "Modo Create: " .. (ctx.settings.createOutputMode or "redstone"), colors.lightBlue)
  ui.button(2, 9, 23, "Sonido: " .. (ctx.settings.clickSounds == false and "OFF" or "ON"), colors.lightBlue)
  ui.text(2, 10, "Periferico Create: " .. (ctx.settings.createPeripheral or "auto"), colors.black, colors.white, w - 2)
  ui.button(2, 11, 18, "Guardar ajustes", colors.green, colors.black)
  ui.text(2, 13, "Salidas Create:", colors.blue, colors.white)
  for i, key in ipairs({ "clutch", "gearbox", "sequencer" }) do
    local side = ctx.settings.createOutputs[key]
    ui.text(2, 14 + i, key .. ": " .. tostring(side), colors.black, colors.white, w - 2)
  end
  ui.text(2, 18, "Valores editables desde /sys/mobile/settings", colors.gray, colors.white, w - 2)
end

function M.touch(ctx, x, y)
  if y == 5 then
    local value = tonumber(lib.prompt(ctx, "Rango radar (1-128):", tostring(ctx.settings.playerRange)))
    if value and value >= 1 and value <= 128 then ctx.settings.playerRange = math.floor(value) end
  elseif y == 7 then
    ctx.settings.createOutputMode = ctx.settings.createOutputMode == "integrator" and "redstone" or "integrator"
  elseif y == 9 then
    ctx.settings.clickSounds = ctx.settings.clickSounds == false
  elseif y == 11 then
    local ok, err = pcall(ctx.saveSettings)
    ctx.notify(ok and "Configuracion guardada" or tostring(err))
    if ok and ctx.playSound then ctx.playSound("action") end
  elseif y >= 15 and y <= 17 then
    local key = ({ "clutch", "gearbox", "sequencer" })[y - 14]
    local side = lib.prompt(ctx, "Lado para " .. key .. ":", ctx.settings.createOutputs[key])
    if side and side ~= "" then ctx.settings.createOutputs[key] = side:lower() end
  end
end

return M
]],
  ['apps/gps.lua'] = [[local ui = require("sys.mobile.ui")
local M = { title = "Pocket GPS" }
local state = {
  x = nil,
  y = nil,
  z = nil,
  message = "Pulsa Localizar para buscar una senal GPS.",
  lastFix = nil,
}

local function locate()
  if not gps or type(gps.locate) ~= "function" then
    state.message = "GPS API no disponible en este equipo."
    return
  end
  state.message = "Buscando satelites..."
  local ok, x, y, z = pcall(gps.locate, 3, false)
  if not ok then
    state.message = "Error GPS: " .. tostring(x)
    return
  end
  if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
    state.message = "Sin senal GPS. Requiere 4 hosts GPS."
    return
  end
  state.x, state.y, state.z = x, y, z
  state.lastFix = os.date("%H:%M:%S")
  state.message = "Posicion obtenida a las " .. state.lastFix
end

function M.open()
  state.message = state.x and ("Ultima posicion: " .. tostring(state.lastFix))
    or "Pulsa Localizar para buscar una senal GPS."
end

function M.draw()
  local w, h = term.getSize()
  ui.fill(2, 3, math.max(1, w - 3), 2, colors.blue)
  ui.text(3, 3, "POSICION DEL ORDENADOR", colors.white, colors.blue, w - 5)
  if state.x then
    ui.text(3, 4, string.format("X %.2f  Y %.2f  Z %.2f", state.x, state.y, state.z),
      colors.white, colors.blue, w - 5)
  else
    ui.text(3, 4, "X --  Y --  Z --", colors.white, colors.blue, w - 5)
  end
  ui.button(2, 6, math.min(12, w - 2), "Localizar", colors.green, colors.black)
  ui.text(2, 8, state.message, colors.black, colors.white, w - 2)
  ui.fill(2, 10, math.max(1, w - 3), 1, colors.lightBlue)
  ui.text(3, 10, "Como funciona", colors.white, colors.lightBlue, w - 5)
  ui.text(2, 12, "GPS usa la API nativa de CC:Tweaked.", colors.black, colors.white, w - 2)
  ui.text(2, 13, "Necesitas 4 ordenadores GPS host", colors.black, colors.white, w - 2)
  ui.text(2, 14, "con modem y gps host en cada uno.", colors.black, colors.white, w - 2)
  if h > 16 then ui.text(2, h - 2, "Las coords son del ordenador, no del jugador.", colors.gray, colors.white, w - 2) end
end

function M.touch(ctx, x, y)
  if y == 6 and x <= 14 then
    locate()
    if state.x and ctx.playSound then ctx.playSound("action") end
  end
end

return M
]],
  ['apps/ores.lua'] = [[local ui = require("sys.mobile.ui")
local M = { title = "Advanced Peripherals Ore Detector" }
local state = { radius = 8, ores = {}, message = "Conecta un Geo Scanner y pulsa Escanear." }

local function isOre(block)
  if type(block) ~= "table" then return false end
  local name = tostring(block.name or block.id or ""):lower()
  if name:find("ore", 1, true) then return true end
  if type(block.tags) == "table" then
    for key, value in pairs(block.tags) do
      local tag = type(key) == "string" and key or tostring(value)
      if tag:lower():find("ores", 1, true) then return true end
    end
  end
  return false
end

local function distanceSquared(block)
  local x, y, z = tonumber(block.x), tonumber(block.y), tonumber(block.z)
  if not x or not y or not z then return math.huge end
  return x * x + y * y + z * z
end

local function scan()
  if not peripheral or type(peripheral.find) ~= "function" then
    state.message = "API de perifericos no disponible."
    state.ores = {}
    return
  end
  local okFind, scanner = pcall(peripheral.find, "geoScanner")
  if not okFind or not scanner then
    state.message = "Geo Scanner no conectado."
    state.ores = {}
    return
  end
  if type(scanner.scan) ~= "function" then
    state.message = "El Geo Scanner no ofrece scan(radius)."
    state.ores = {}
    return
  end
  state.message = "Escaneando radio " .. state.radius .. "..."
  local ok, result = pcall(scanner.scan, state.radius)
  if not ok then
    state.message = "Fallo al escanear: " .. tostring(result)
    state.ores = {}
    return
  end
  if type(result) ~= "table" then
    state.message = "El Geo Scanner devolvio un resultado invalido."
    state.ores = {}
    return
  end
  state.ores = {}
  for _, block in pairs(result) do
    if isOre(block) then state.ores[#state.ores + 1] = block end
  end
  table.sort(state.ores, function(a, b) return distanceSquared(a) < distanceSquared(b) end)
  state.message = #state.ores == 0 and "No se encontraron menas en el escaneo."
    or (#state.ores .. " bloques con etiqueta/nombre de mena.")
end

function M.open()
  state.ores = {}
  state.message = "Conecta un Geo Scanner y pulsa Escanear."
end

function M.draw()
  local w, h = term.getSize()
  ui.button(2, 3, math.min(12, w - 2), "Escanear", colors.green, colors.black)
  ui.button(16, 3, math.min(10, math.max(1, w - 16)), "Radio " .. state.radius, colors.lightBlue)
  ui.text(2, 5, state.message, colors.blue, colors.white, w - 2)
  ui.fill(2, 6, math.max(1, w - 3), 1, colors.blue)
  ui.text(3, 6, "MENAS MAS CERCANAS", colors.white, colors.blue, w - 5)
  if #state.ores == 0 then
    ui.text(2, 8, "El resultado aparecera aqui.", colors.gray, colors.white, w - 2)
    return
  end
  for i = 1, math.min(#state.ores, h - 9) do
    local block = state.ores[i]
    local name = tostring(block.name or block.id or "mena")
    name = name:gsub("^.+:", "")
    local x, y, z = tostring(block.x or "?"), tostring(block.y or "?"), tostring(block.z or "?")
    local row = 8 + i
    ui.fill(2, row, math.max(1, w - 3), 1, i % 2 == 0 and colors.lightGray or colors.white)
    ui.text(3, row, name .. "  " .. x .. "," .. y .. "," .. z,
      colors.black, i % 2 == 0 and colors.lightGray or colors.white, w - 5)
  end
end

function M.touch(ctx, x, y)
  local w = term.getSize()
  if y == 3 and x <= 14 then
    scan()
    if state.message:find("bloques con etiqueta", 1, true) and ctx.playSound then
      ctx.playSound("action")
    end
  elseif y == 3 and x >= 15 and x <= w then
    state.radius = state.radius >= 8 and 1 or state.radius + 1
  end
end

return M
]],
  ['apps/calculator.lua'] = [[local ui = require("sys.mobile.ui")
local lib = require("sys.mobile.lib")
local M = { title = "Pocket Calculator" }
local state = { expression = "", result = "Introduce una expresion." }

local function evaluate(source)
  local position = 1
  local parseExpression
  local function skipSpace()
    while source:sub(position, position):match("%s") do position = position + 1 end
  end
  local function parseNumber()
    skipSpace()
    local token = source:sub(position):match("^%d+%.?%d*") or source:sub(position):match("^%.%d+")
    if not token then error("Se esperaba un numero") end
    position = position + #token
    return tonumber(token)
  end
  local function parsePrimary()
    skipSpace()
    if source:sub(position, position) == "(" then
      position = position + 1
      local value = parseExpression()
      skipSpace()
      if source:sub(position, position) ~= ")" then error("Falta cerrar parentesis") end
      position = position + 1
      return value
    end
    return parseNumber()
  end
  local parseUnary
  local function parsePower()
    local value = parsePrimary()
    skipSpace()
    if source:sub(position, position) == "^" then
      position = position + 1
      value = value ^ parseUnary()
    end
    return value
  end
  parseUnary = function()
    skipSpace()
    local char = source:sub(position, position)
    if char == "+" then position = position + 1; return parseUnary() end
    if char == "-" then position = position + 1; return -parseUnary() end
    return parsePower()
  end
  local function parseTerm()
    local value = parseUnary()
    while true do
      skipSpace()
      local operator = source:sub(position, position)
      if operator ~= "*" and operator ~= "/" and operator ~= "%" then break end
      position = position + 1
      local right = parseUnary()
      if (operator == "/" or operator == "%") and right == 0 then error("Division entre cero") end
      if operator == "*" then value = value * right
      elseif operator == "/" then value = value / right
      else value = value % right end
    end
    return value
  end
  parseExpression = function()
    local value = parseTerm()
    while true do
      skipSpace()
      local operator = source:sub(position, position)
      if operator ~= "+" and operator ~= "-" then break end
      position = position + 1
      local right = parseTerm()
      value = operator == "+" and value + right or value - right
    end
    return value
  end
  local result = parseExpression()
  skipSpace()
  if position <= #source then error("Caracter inesperado: " .. source:sub(position, position)) end
  if result ~= result or result == math.huge or result == -math.huge then error("Resultado fuera de rango") end
  return result
end

function M.draw()
  local w = term.getSize()
  ui.fill(2, 3, math.max(1, w - 3), 3, colors.black)
  ui.text(3, 3, state.expression ~= "" and state.expression or "Pocket Calc",
    colors.lightBlue, colors.black, w - 5)
  ui.text(3, 4, tostring(state.result), colors.white, colors.black, w - 5)
  ui.button(2, 7, math.min(16, w - 2), "Calcular", colors.green, colors.black)
  ui.button(2, 9, math.min(16, w - 2), "Nueva cuenta", colors.lightBlue)
  ui.text(2, 12, "Operadores: + - * / % ^", colors.gray, colors.white, w - 2)
  ui.text(2, 13, "Admite parentesis y numeros decimales.", colors.gray, colors.white, w - 2)
end

function M.touch(ctx, _, y)
  if y ~= 7 and y ~= 9 then return end
  local expression = lib.prompt(ctx, "Cuenta:", state.expression)
  if not expression or expression == "" then return end
  state.expression = expression
  local ok, result = pcall(evaluate, expression)
  state.result = ok and tostring(result) or tostring(result)
  if ok and ctx.playSound then ctx.playSound("action") end
end

return M
]],
  ['apps/notes.lua'] = [[local ui = require("sys.mobile.ui")
local lib = require("sys.mobile.lib")
local M = { title = "Pocket Notes" }
local PATH = "/notes/Quick Notes.txt"
local state = { text = "", message = "Notas guardadas en /notes." }

local function load()
  if not fs.exists(PATH) then state.text = ""; return true end
  local text, err = lib.readFile(PATH, 12000)
  if not text then state.message = tostring(err); return false end
  state.text, state.message = text, "Nota cargada."
  return true
end

function M.open()
  load()
end

function M.draw()
  local w, h = term.getSize()
  ui.button(2, 3, math.min(12, w - 2), "Editar", colors.green, colors.black)
  ui.button(16, 3, math.min(10, math.max(1, w - 16)), "Guardar", colors.blue)
  ui.text(2, 5, state.message, colors.blue, colors.white, w - 2)
  ui.fill(2, 6, math.max(1, w - 3), 1, colors.lightBlue)
  ui.text(3, 6, "QUICK NOTES", colors.white, colors.lightBlue, w - 5)
  local lines = {}
  for line in (state.text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
  for i = 1, math.min(#lines, h - 9) do
    ui.text(2, 7 + i, lines[i], colors.black, colors.white, w - 2)
  end
end

function M.touch(ctx, x, y)
  local w = term.getSize()
  if y == 3 and x <= 14 then
    print("Editor de notas. Escribe una linea con . para terminar.")
    local lines = {}
    while true do
      local line = read()
      if line == "." then break end
      lines[#lines + 1] = line
    end
    state.text = table.concat(lines, "\n")
    state.message = "Cambios sin guardar."
  elseif y == 3 and x > 14 and x <= w then
    local ok, err = lib.writeFile(PATH, state.text)
    state.message = ok and "Nota guardada." or ("Error: " .. tostring(err))
    if ok and ctx.playSound then ctx.playSound("action") end
  end
end

return M
]],
  ['apps/clock.lua'] = [[local ui = require("sys.mobile.ui")
local lib = require("sys.mobile.lib")
local M = { title = "Pocket Clock" }
local state = { started = nil, elapsed = 0, timerEnd = nil, message = "Reloj y cronometro" }

local function now()
  if os.epoch then return os.epoch("utc") / 1000 end
  return os.clock()
end

local function elapsed()
  return state.elapsed + (state.started and (now() - state.started) or 0)
end

local function format(seconds)
  seconds = math.max(0, math.floor(seconds))
  return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end

function M.draw(ctx)
  local w = term.getSize()
  local clock = os.date("%H:%M:%S")
  ui.fill(2, 3, math.max(1, w - 3), 3, colors.blue)
  ui.text(3, 3, "HORA LOCAL", colors.white, colors.blue, w - 5)
  ui.text(3, 4, clock, colors.white, colors.blue, w - 5)
  ui.text(2, 7, "Cronometro: " .. format(elapsed()), colors.black, colors.white, w - 2)
  ui.button(2, 9, math.min(10, w - 2), state.started and "Pausar" or "Iniciar", colors.green, colors.black)
  ui.button(14, 9, math.min(10, math.max(1, w - 14)), "Reiniciar", colors.lightBlue)
  if state.timerEnd then
    local remaining = state.timerEnd - now()
    ui.text(2, 12, "Temporizador: " .. format(remaining), colors.blue, colors.white, w - 2)
  else
    ui.text(2, 12, state.message, colors.gray, colors.white, w - 2)
  end
  ui.button(2, 14, math.min(w - 2, 20), "Programar temporizador", colors.blue)
end

function M.tick(ctx)
  if state.timerEnd and now() >= state.timerEnd then
    state.timerEnd = nil
    state.message = "Temporizador terminado."
    ctx.notify("Temporizador terminado")
    if ctx.playSound then ctx.playSound("action") end
  end
end

function M.touch(ctx, x, y)
  if y == 9 and x < 13 then
    if state.started then
      state.elapsed = elapsed()
      state.started = nil
    else
      state.started = now()
    end
  elseif y == 9 then
    state.started, state.elapsed, state.timerEnd = nil, 0, nil
  elseif y == 14 then
    local seconds = tonumber(lib.prompt(ctx, "Segundos (1-86400):", "60"))
    if seconds and seconds >= 1 and seconds <= 86400 then
      state.timerEnd = now() + math.floor(seconds)
      state.message = "Temporizador activo."
    else
      state.message = "Duracion no valida."
    end
  end
end

return M
]],
  ['apps/redstone.lua'] = [[local ui = require("sys.mobile.ui")
local M = { title = "Pocket Redstone" }
local sides = { "left", "right", "top", "bottom", "front", "back" }

function M.draw()
  local w = term.getSize()
  ui.text(2, 3, "Salidas del ordenador", colors.blue, colors.white, w - 2)
  if not redstone or not redstone.getOutput then
    ui.text(2, 5, "API de redstone no disponible.", colors.red, colors.white, w - 2)
    return
  end
  for i, side in ipairs(sides) do
    local y = 5 + i * 2
    local active = redstone.getOutput(side)
    ui.button(2, y, math.min(w - 3, 20), side .. ": " .. (active and "ON" or "OFF"),
      active and colors.green or colors.gray, colors.white)
  end
  ui.text(2, 18, "Toca una salida para conmutarla.", colors.gray, colors.white, w - 2)
end

function M.touch(ctx, _, y)
  if not redstone or not redstone.getOutput or not redstone.setOutput then
    ctx.notify("La API de redstone no esta disponible.")
    return
  end
  local index = math.floor((y - 5) / 2)
  local side = sides[index]
  if side and y == 5 + index * 2 then
    local ok, err = pcall(redstone.setOutput, side, not redstone.getOutput(side))
    if not ok then ctx.notify("Redstone: " .. tostring(err))
    elseif ctx.playSound then ctx.playSound("action") end
  end
end

return M
]],
  ['apps/inventory.lua'] = [[local ui = require("sys.mobile.ui")
local M = { title = "Pocket Inventory" }
local state = { items = {}, message = "Pulsa Actualizar para leer inventarios.", scroll = 0 }

local function refresh()
  state.items = {}
  if not peripheral or type(peripheral.find) ~= "function" then
    state.message = "API de perifericos no disponible."
    return
  end
  local ok, inventories = pcall(peripheral.find, "inventory")
  if not ok or not inventories then
    state.message = "No se encontro un inventario conectado."
    return
  end
  if type(inventories.list) ~= "function" then
    state.message = "El periferico no ofrece list()."
    return
  end
  local listed, contents = pcall(inventories.list)
  if not listed or type(contents) ~= "table" then
    state.message = "No se pudo leer el inventario."
    return
  end
  for slot, item in pairs(contents) do
    if type(item) == "table" then
      local detail = item
      if type(inventories.getItemDetail) == "function" then
        local okDetail, value = pcall(inventories.getItemDetail, slot)
        if okDetail and type(value) == "table" then detail = value end
      end
      state.items[#state.items + 1] = {
        slot = slot,
        name = detail.displayName or detail.name or item.name or "Objeto",
        count = item.count or detail.count or 0,
      }
    end
  end
  table.sort(state.items, function(a, b) return a.slot < b.slot end)
  state.scroll = 0
  state.message = #state.items .. " stacks en el primer inventario detectado."
end

function M.open()
  state.scroll = 0
end

function M.draw()
  local w, h = term.getSize()
  ui.button(2, 3, math.min(13, w - 2), "Actualizar", colors.green, colors.black)
  ui.text(2, 5, state.message, colors.blue, colors.white, w - 2)
  ui.fill(2, 6, math.max(1, w - 3), 1, colors.blue)
  ui.text(3, 6, "SLOT   OBJETO                 CANT.", colors.white, colors.blue, w - 5)
  for i = 1, math.max(0, h - 12) do
    local item = state.items[state.scroll + i]
    if not item then break end
    local name = item.name
    local row = 6 + i
    local bg = i % 2 == 0 and colors.lightGray or colors.white
    ui.fill(2, row, math.max(1, w - 3), 1, bg)
    ui.text(3, row, string.format("%-4s %-18s %5s", tostring(item.slot), name, tostring(item.count)),
      colors.black, bg, w - 5)
  end
  ui.button(2, h - 2, math.min(8, w - 2), "Arriba", colors.lightBlue)
  ui.button(math.max(11, w - 9), h - 2, math.min(8, w - 2), "Abajo", colors.lightBlue)
end

function M.touch(_, x, y)
  local _, h = term.getSize()
  if y == 3 then refresh()
  elseif y == h - 2 and x < 10 then
    state.scroll = math.max(0, state.scroll - 5)
  elseif y == h - 2 then
    state.scroll = math.min(math.max(0, #state.items - 1), state.scroll + 5)
  end
end

return M
]],
  ['apps/youtube.lua'] = [[local ui = require("sys.mobile.ui")
local lib = require("sys.mobile.lib")
local M = { title = "YouTube Terminal" }

local DATA_PATH = "/sys/mobile/youtube"
local MAX_RESPONSE = 65536
local MAX_ITEMS = 40
local state = {
  mode = "results",
  query = "",
  results = {},
  saved = {},
  history = {},
  selected = nil,
  returnMode = "results",
  page = 1,
  message = "Busca videos. Requiere HTTP y un servidor Invidious disponible.",
}

local function loadData()
  if not fs.exists(DATA_PATH) then return end
  local file, err = fs.open(DATA_PATH, "r")
  if not file then state.message = "No se pudo leer favoritos: " .. tostring(err); return end
  local raw = file.readAll()
  file.close()
  local ok, data = pcall(textutils.unserialize, raw or "")
  if not ok or type(data) ~= "table" then
    state.message = "No se pudieron cargar favoritos e historial."
    return
  end
  if type(data.saved) == "table" then state.saved = data.saved end
  if type(data.history) == "table" then state.history = data.history end
end

local function saveData()
  local parent = fs.getDir(DATA_PATH)
  if not fs.exists(parent) then fs.makeDir(parent) end
  local file, err = fs.open(DATA_PATH, "w")
  if not file then return nil, err end
  file.write(textutils.serialize({ saved = state.saved, history = state.history }))
  file.close()
  return true
end

local function readResponse(url, limit)
  if not http or type(http.get) ~= "function" then
    return nil, "HTTP no está habilitado en CraftOS."
  end
  local ok, response, reason = pcall(http.get, url, {
    ["User-Agent"] = "XP-Pocket-Mobile/1.0",
    ["Accept"] = "application/json",
  })
  if not ok or not response then
    return nil, "No se pudo conectar: " .. tostring(ok and reason or response)
  end

  local codeOk, code = pcall(function()
    if response.getResponseCode then return response.getResponseCode() end
  end)
  if codeOk and type(code) == "number" and code >= 400 then
    pcall(response.close)
    return nil, "El servidor respondió HTTP " .. code .. "."
  end

  local chunks, size = {}, 0
  local readOk, readError = pcall(function()
    while size <= limit do
      local chunk = response.read(math.min(4096, limit + 1 - size))
      if not chunk or chunk == "" then break end
      chunks[#chunks + 1] = chunk
      size = size + #chunk
    end
  end)
  pcall(response.close)
  if not readOk then return nil, "Error leyendo la respuesta: " .. tostring(readError) end
  if size > limit then return nil, "La respuesta supera el límite de tamaño." end
  return table.concat(chunks)
end

local function decodeJson(raw)
  local ok, result = pcall(textutils.unserializeJSON, raw or "")
  if not ok or type(result) ~= "table" then
    return nil, "El servidor devolvió JSON no válido."
  end
  return result
end

local function encode(value)
  return (tostring(value):gsub("([^%w%-_%.~])", function(char)
    return string.format("%%%02X", string.byte(char))
  end))
end

local function findInstances()
  local raw, err = readResponse("https://api.invidious.io/instances.json?sort_by=api", 32768)
  if not raw then return nil, err end
  local instances, decodeError = decodeJson(raw)
  if not instances then return nil, decodeError end

  local available = {}
  for _, entry in ipairs(instances) do
    local details = type(entry) == "table" and entry[2]
    local uri = type(details) == "table" and details.uri
    if type(uri) == "string" and uri:match("^https://")
      and details.api == true and details.type == "https" then
      available[#available + 1] = uri:gsub("/+$", "")
      if #available >= 3 then break end
    end
  end
  if #available == 0 then
    return nil, "No se encontró un servidor HTTPS con API disponible."
  end
  return available
end

local function normalizeVideo(video)
  if type(video) ~= "table" or type(video.videoId) ~= "string"
    or not video.videoId:match("^[%w_-]+$")
    or type(video.title) ~= "string" then
    return nil
  end
  local title = video.title:gsub("[%c]", " "):gsub("%s+", " ")
  local author = tostring(video.author or "Canal desconocido"):gsub("[%c]", " "):gsub("%s+", " ")
  return {
    videoId = video.videoId,
    title = title,
    author = author,
    duration = tostring(video.lengthSeconds or "--"),
    views = tostring(video.viewCount or "--"),
    published = tostring(video.publishedText or ""),
  }
end

local function search(query, page)
  state.query = query
  state.mode, state.selected = "results", nil
  state.page = page or 1
  state.results = {}
  state.message = "Buscando..."

  local instances, instanceError = findInstances()
  if not instances then state.message = instanceError; return end
  local lastError
  for _, instance in ipairs(instances) do
    local url = instance .. "/api/v1/search?q=" .. encode(query) .. "&type=video&page=" .. state.page
    local raw, requestError = readResponse(url, MAX_RESPONSE)
    if raw then
      local response, decodeError = decodeJson(raw)
      if response and type(response.error) ~= "string" then
        for _, item in ipairs(response) do
          local video = normalizeVideo(item)
          if video then state.results[#state.results + 1] = video end
        end
        state.message = #state.results > 0
          and ("Resultados: " .. #state.results .. " | Fuente: Invidious")
          or "No se encontraron videos."
        return
      end
      lastError = response and response.error or decodeError
    else
      lastError = requestError
    end
  end
  state.message = lastError or "No se pudo completar la búsqueda."
end

local function activeItems()
  if state.mode == "saved" then return state.saved end
  if state.mode == "history" then return state.history end
  return state.results
end

local function remember(video)
  for index = #state.history, 1, -1 do
    if state.history[index].videoId == video.videoId then
      table.remove(state.history, index)
    end
  end
  table.insert(state.history, 1, video)
  while #state.history > MAX_ITEMS do table.remove(state.history) end
  local ok, err = saveData()
  if not ok then state.message = "No se guardó el historial: " .. tostring(err) end
end

local function openSearch(ctx)
  local query = lib.prompt(ctx, "Buscar en YouTube:", state.query)
  if query and query:match("%S") then search(query) end
end

local function selectVideo(video)
  state.returnMode = state.mode
  state.selected = video
  state.mode = "detail"
  remember(video)
end

function M.open()
  loadData()
end

function M.draw()
  local width, height = term.getSize()
  ui.button(2, 3, 7, "Buscar", colors.red)
  ui.button(10, 3, 8, "Favoritos", colors.lightBlue)
  ui.button(19, 3, 8, "Historial", colors.lightBlue)
  ui.fill(1, 4, width, 1, colors.gray)
  ui.text(2, 4, state.message, colors.white, colors.gray, width - 2)

  if state.mode == "detail" and state.selected then
    local video = state.selected
    ui.button(2, 5, 7, "Lista", colors.blue)
    ui.button(10, 5, 8, "Guardar", colors.green, colors.black)
    ui.text(2, 7, video.title, colors.blue, colors.white, width - 2)
    ui.text(2, 9, "Canal: " .. video.author, colors.black, colors.white, width - 2)
    ui.text(2, 10, "Duracion: " .. video.duration .. " s", colors.black, colors.white, width - 2)
    ui.text(2, 11, "Vistas: " .. video.views, colors.black, colors.white, width - 2)
    ui.text(2, 13, "youtu.be/" .. video.videoId, colors.blue, colors.white, width - 2)
    ui.text(2, 15, "CraftOS no reproduce video;", colors.red, colors.white, width - 2)
    ui.text(2, 16, "abre el enlace externamente.", colors.red, colors.white, width - 2)
    return
  end

  local items = activeItems()
  local firstRow, lastRow = 6, height - 3
  local visible = math.max(0, lastRow - firstRow + 1)
  local pageSize = math.max(1, math.floor(visible / 2))
  local offset = state.mode == "results" and 0 or (state.page - 1) * pageSize
  for itemIndex = 1, pageSize do
    local item = items[offset + itemIndex]
    if item then
      local y = firstRow + (itemIndex - 1) * 2
      local marker = state.mode == "results" and tostring(offset + itemIndex) or ">"
      ui.text(2, y, marker .. " " .. item.title, colors.blue, colors.white, width - 2)
      ui.fill(2, y + 1, math.max(1, width - 3), 1, colors.lightGray)
      ui.text(3, y + 1, item.author .. " | " .. item.duration .. " s",
        colors.gray, colors.lightGray, width - 4)
    end
  end
  if visible > 0 then
    ui.button(2, height - 1, 8, "< Atras", colors.lightBlue)
    ui.button(math.max(11, width - 9), height - 1, 8, "Mas >", colors.lightBlue)
  end
end

function M.touch(ctx, x, y)
  local width, height = term.getSize()
  if y == 3 then
    if x < 10 then openSearch(ctx)
    elseif x < 19 then
      state.mode, state.page, state.selected = "saved", 1, nil
      state.message = #state.saved .. " videos guardados."
    else
      state.mode, state.page, state.selected = "history", 1, nil
      state.message = #state.history .. " videos en el historial."
    end
    return
  end

  if state.mode == "detail" and state.selected then
    if y == 5 and x < 10 then
      state.mode, state.selected = state.returnMode, nil
    elseif y == 5 and x < 19 then
      local exists = false
      for _, item in ipairs(state.saved) do
        if item.videoId == state.selected.videoId then exists = true; break end
      end
      if not exists then
        table.insert(state.saved, 1, state.selected)
        while #state.saved > MAX_ITEMS do table.remove(state.saved) end
      end
      local ok, err = saveData()
      state.message = ok and "Video guardado en favoritos."
        or ("No se guardó: " .. tostring(err))
    end
    return
  end

  if y == height - 1 then
    if x < 11 then
      if state.mode == "results" and state.page > 1 then
        search(state.query, state.page - 1)
      else
        state.page = math.max(1, state.page - 1)
      end
    elseif state.mode == "results" and state.query ~= "" then
      search(state.query, state.page + 1)
    else
      local visible = math.max(1, height - 8)
      local pageSize = math.max(1, math.floor(visible / 2))
      if state.page * pageSize < #activeItems() then state.page = state.page + 1 end
    end
    return
  end

  local firstRow, lastRow = 6, height - 3
  if y >= firstRow and y <= lastRow then
    local visible = math.max(1, lastRow - firstRow + 1)
    local pageSize = math.max(1, math.floor(visible / 2))
    local offset = state.mode == "results" and 0 or (state.page - 1) * pageSize
    local index = offset + math.floor((y - firstRow) / 2) + 1
    local item = activeItems()[index]
    if item then selectVideo(item) end
  end
end

return M
]],
  ['apps/map.lua'] = [[local ui = require("sys.mobile.ui")
local lib = require("sys.mobile.lib")
local M = { title = "Google Maps Pocket" }

local DATA_PATH = "/sys/mobile/map"
local MAX_POINTS = 400
local SCALES = { 1, 4, 16, 64 }
local state = {
  x = nil,
  y = nil,
  z = nil,
  dimension = "--",
  points = {},
  destination = nil,
  zoom = 2,
  nextUpdate = 0,
  message = "Pulsa GPS para centrar el mapa.",
}

local function save()
  local parent = fs.getDir(DATA_PATH)
  if not fs.exists(parent) then fs.makeDir(parent) end
  local file, err = fs.open(DATA_PATH, "w")
  if not file then return nil, err end
  file.write(textutils.serialize({
    points = state.points,
    destination = state.destination,
    zoom = state.zoom,
    dimension = state.dimension,
  }))
  file.close()
  return true
end

local function load()
  if not fs.exists(DATA_PATH) then return end
  local file, err = fs.open(DATA_PATH, "r")
  if not file then state.message = "No se pudo leer el mapa: " .. tostring(err); return end
  local raw = file.readAll()
  file.close()
  local ok, data = pcall(textutils.unserialize, raw or "")
  if not ok or type(data) ~= "table" then
    state.message = "No se pudieron cargar los datos del mapa."
    return
  end
  if type(data.points) == "table" then
    for _, point in ipairs(data.points) do
      if type(point) == "table" and type(point.x) == "number" and type(point.z) == "number" then
        state.points[#state.points + 1] = { x = point.x, z = point.z }
        if #state.points >= MAX_POINTS then break end
      end
    end
  end
  if type(data.destination) == "table"
    and type(data.destination.x) == "number"
    and type(data.destination.z) == "number" then
    state.destination = { x = data.destination.x, z = data.destination.z }
  end
  if type(data.zoom) == "number" and SCALES[data.zoom] then state.zoom = data.zoom end
  if type(data.dimension) == "string" then state.dimension = data.dimension end
end

local function recordPosition(x, z)
  local previous = state.points[#state.points]
  if not previous or math.floor(previous.x) ~= math.floor(x)
    or math.floor(previous.z) ~= math.floor(z) then
    state.points[#state.points + 1] = { x = x, z = z }
    while #state.points > MAX_POINTS do table.remove(state.points, 1) end
    return true
  end
  return false
end

local function locate(ctx, timeout)
  state.nextUpdate = os.clock() + 5
  if not gps or type(gps.locate) ~= "function" then
    state.message = "La API GPS no está disponible."
    return
  end
  state.message = "Buscando señal GPS..."
  local ok, x, y, z = pcall(gps.locate, timeout or 3, false)
  if not ok then
    state.message = "Error GPS: " .. tostring(x)
    return
  end
  if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
    state.message = "Sin señal: configura 4 hosts GPS con modem."
    return
  end

  local dimension = tostring((ctx.world and ctx.world.dimension) or "--")
  local changedDimension = state.dimension ~= "--" and dimension ~= "--"
    and state.dimension ~= dimension
  if changedDimension then
    state.points = {}
    state.destination = nil
    state.message = "Cambió la dimensión; historial del mapa reiniciado."
  else
    state.message = "Mapa centrado en tu posición."
  end
  state.x, state.y, state.z = x, y, z
  state.dimension = dimension
  local changedPosition = recordPosition(x, z)
  if changedPosition or changedDimension then
    local saved, err = save()
    if not saved then state.message = "No se guardó el mapa: " .. tostring(err) end
  end
  state.nextUpdate = os.clock() + 5
end

local function setDestination(ctx)
  local initial = state.destination
    and (tostring(state.destination.x) .. " " .. tostring(state.destination.z)) or ""
  local value = lib.prompt(ctx, "Destino X Z (vacio borra):", initial)
  if value == nil then return end
  if value == "" then
    state.destination = nil
    state.message = "Destino borrado."
  else
    local x, z = value:match("^%s*(-?[%d%.]+)%s*[, ]%s*(-?[%d%.]+)%s*$")
    x, z = tonumber(x), tonumber(z)
    if not x or not z then
      state.message = "Coordenadas no válidas. Escribe X Z."
      return
    end
    state.destination = { x = x, z = z }
    state.message = "Destino guardado."
  end
  local saved, err = save()
  if not saved then state.message = "No se guardó el mapa: " .. tostring(err) end
end

local function direction(dx, dz)
  if dx == 0 and dz == 0 then return "aqui" end
  local ax, az = math.abs(dx), math.abs(dz)
  if az > ax * 2 then return dz < 0 and "N" or "S" end
  if ax > az * 2 then return dx > 0 and "E" or "O" end
  if dx > 0 then return dz < 0 and "NE" or "SE" end
  return dz < 0 and "NO" or "SO"
end

local function controls(width)
  if width < 22 then
    return { gpsX = 2, gpsWidth = 5, minusX = 8, plusX = 11, zoomWidth = 2,
      destinationX = 14, destinationWidth = math.max(1, width - 14) }
  end
  return { gpsX = 2, gpsWidth = 6, minusX = 9, plusX = 13, zoomWidth = 3,
    destinationX = 17, destinationWidth = math.min(9, width - 16) }
end

local function drawMap(width, top, bottom)
  local mapWidth = math.max(1, width - 4)
  local mapHeight = math.max(1, bottom - top + 1)
  local centerColumn = math.floor((mapWidth + 1) / 2)
  local centerRow = math.floor((mapHeight + 1) / 2)
  local scale = SCALES[state.zoom]

  for row = 1, mapHeight do
    local line = {}
    for column = 1, mapWidth do
      line[column] = (row == centerRow or column == centerColumn) and "+" or " "
    end

    local function plot(x, z, marker)
      if not state.x then return end
      local column = centerColumn + math.floor((x - state.x) / scale + 0.5)
      local row = centerRow + math.floor((z - state.z) / scale + 0.5)
      if column >= 1 and column <= mapWidth and row >= 1 and row <= mapHeight then
        line[column] = marker
      end
    end

    for _, point in ipairs(state.points) do plot(point.x, point.z, "o") end
    if state.destination then plot(state.destination.x, state.destination.z, "X") end
    if state.x then plot(state.x, state.z, "@") end

    term.setCursorPos(3, top + row - 1)
    for column = 1, mapWidth do
      local marker = line[column]
      if marker == "@" then
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.blue)
      elseif marker == "X" then
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.red)
      elseif marker == "+" then
        term.setTextColor(colors.gray)
        term.setBackgroundColor(colors.lightGray)
      elseif marker == "o" then
        term.setTextColor(colors.green)
        term.setBackgroundColor(colors.white)
      else
        term.setTextColor(colors.lightGray)
        term.setBackgroundColor(colors.white)
      end
      term.write(marker)
    end
  end
  term.setBackgroundColor(colors.white)
end

function M.open(ctx)
  state.x, state.y, state.z = nil, nil, nil
  state.points = {}
  state.destination = nil
  state.zoom = 2
  state.dimension = "--"
  load()
  if state.dimension == "--" and ctx.world then
    state.dimension = tostring(ctx.world.dimension or "--")
  end
  state.nextUpdate = os.clock() + 2
end

function M.tick(ctx)
  if os.clock() >= state.nextUpdate then locate(ctx, 1) end
end

function M.draw(ctx)
  local width, height = term.getSize()
  local layout = controls(width)
  ui.button(layout.gpsX, 3, layout.gpsWidth, "GPS", colors.green, colors.black)
  ui.button(layout.minusX, 3, layout.zoomWidth, "-", colors.lightBlue)
  ui.button(layout.plusX, 3, layout.zoomWidth, "+", colors.lightBlue)
  ui.button(layout.destinationX, 3, layout.destinationWidth,
    width < 22 and "Dst" or "Destino", colors.blue)

  local mapTop = 5
  local footer = height - 3
  ui.text(2, 4, "N ^ " .. state.dimension:gsub("^minecraft:", ""),
    colors.blue, colors.white, width - 2)
  drawMap(width, mapTop, math.max(mapTop, footer - 1))

  if state.x then
    ui.text(2, footer, string.format("X %.0f Y %.0f Z %.0f  1:%d",
      state.x, state.y, state.z, SCALES[state.zoom]), colors.black, colors.white, width - 2)
  else
    ui.text(2, footer, "Sin posicion GPS  |  1:" .. SCALES[state.zoom],
      colors.gray, colors.white, width - 2)
  end
  if state.destination and state.x then
    local dx, dz = state.destination.x - state.x, state.destination.z - state.z
    local distance = math.floor(math.sqrt(dx * dx + dz * dz) + 0.5)
    ui.text(2, footer + 1, "Destino: " .. distance .. "m " .. direction(dx, dz),
      colors.red, colors.white, width - 2)
    ui.text(2, footer + 2, state.message, colors.gray, colors.white, width - 2)
  else
    ui.text(2, footer + 1, state.message, colors.gray, colors.white, width - 2)
  end
end

function M.touch(ctx, x, y)
  local width = term.getSize()
  if y == 3 then
    local layout = controls(width)
    if x >= layout.gpsX and x < layout.gpsX + layout.gpsWidth then
      locate(ctx)
      if state.x and ctx.playSound then ctx.playSound("action") end
    elseif x >= layout.minusX and x < layout.minusX + layout.zoomWidth then
      state.zoom = math.max(1, state.zoom - 1)
      local ok, err = save()
      if not ok then state.message = "No se guardó el zoom: " .. tostring(err) end
    elseif x >= layout.plusX and x < layout.plusX + layout.zoomWidth then
      state.zoom = math.min(#SCALES, state.zoom + 1)
      local ok, err = save()
      if not ok then state.message = "No se guardó el zoom: " .. tostring(err) end
    elseif x >= layout.destinationX
      and x < layout.destinationX + layout.destinationWidth then
      setDestination(ctx)
    end
  end
end

return M
]],
}

local function fail(message)
  error(message, 0)
end

local function ensureDir(path)
  if path == "" or path == "/" then return end
  if fs.exists(path) then
    if not fs.isDir(path) then fail("La ruta no es una carpeta: " .. path) end
    return
  end
  local parent = fs.getDir(path)
  if parent ~= path and parent ~= "" then ensureDir(parent) end
  fs.makeDir(path)
end

local function writeFile(path, content)
  ensureDir(fs.getDir(path))
  local handle, reason = fs.open(path, "w")
  if not handle then fail("No se pudo escribir " .. path .. ": " .. tostring(reason)) end
  local ok, writeError = pcall(handle.write, content)
  handle.close()
  if not ok then fail("Error escribiendo " .. path .. ": " .. tostring(writeError)) end
end

local function install()
  local stamp = tostring(os.epoch and os.epoch("utc") or os.time())
  local stage = "/.xp_pocket_mobile_stage_" .. stamp
  local backup = "/xp_mobile_backups/" .. stamp
  if fs.exists(stage) then fail("Ya existe el directorio temporal: " .. stage) end
  ensureDir(stage)

  for path, content in pairs(FILES) do
    writeFile(fs.combine(stage, path), content)
  end

  local installed, backedUp = {}, {}
  local ok, reason = pcall(function()
    for path in pairs(FILES) do
      local destination = "/" .. path
      local stagedFile = fs.combine(stage, path)
      ensureDir(fs.getDir(destination))
      if fs.exists(destination) then
        if fs.isDir(destination) then fail("No se reemplazara una carpeta: " .. destination) end
        local saved = fs.combine(backup, path)
        ensureDir(fs.getDir(saved))
        fs.move(destination, saved)
        backedUp[#backedUp + 1] = { destination, saved }
      end
      fs.move(stagedFile, destination)
      installed[#installed + 1] = destination
    end
  end)

  if not ok then
    for i = #installed, 1, -1 do
      if fs.exists(installed[i]) then fs.delete(installed[i]) end
    end
    for i = #backedUp, 1, -1 do
      local item = backedUp[i]
      if fs.exists(item[2]) and not fs.exists(item[1]) then fs.move(item[2], item[1]) end
    end
    if fs.exists(stage) then fs.delete(stage) end
    fail("Instalacion cancelada; se restauraron los archivos anteriores. " .. tostring(reason))
  end

  if fs.exists(stage) then fs.delete(stage) end
  print("Windows XP Pocket Mobile instalado correctamente.")
  print("Archivos instalados: " .. tostring(#installed))
  if #backedUp > 0 then
    print("Copia de seguridad de los archivos previos: " .. backup)
  end
  print("Reinicia con: reboot")
end

local ok, reason = pcall(install)
if not ok then
  printError("XP Pocket Mobile: " .. tostring(reason))
end
