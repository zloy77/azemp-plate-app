ac.log('PlateText: script yukleniyor (v3.17-server)')
-- ============================================================
-- SERVER-SIDE VERSIYA: oyuncular hec nə yuklemir.
-- Server csp_extra_options.ini icinde bu faylin URL-i verilir.
-- Gorsel fayllar (plate_bg.png, logo.png, glyphs/) internetde olmalidir.
-- ============================================================
local ASSET_BASE = 'https://raw.githubusercontent.com/zloy77/azemp-plate-app/main/'   -- <-- BUNU DEYIS (sonu '/' ile bitsin)
local TOGGLE_KEY = ui.KeyIndex.M       -- <-- plaka penceresini acib-baglayan duymə (oyunda Controls-dan da deyisdirile biler)
local function asset(p) return ASSET_BASE .. p end

-- ============================================================
-- CONFIG: sadece burayi duzenle
-- ============================================================
local CONFIG = {
  -- ===== PLAKA TAPMA =====
  -- Buraya istediyin qeder material adi elave ede bilersen. HAMISI yoxlanilir,
  -- tapilan butun meshler (on + arxa nomre) birlikde deyisdirilir.
  materialNames = {
    'license_plate(520x110)',
    'license_plate?520x110?',
    'license_plate*',
    'license_plate', 'License_Plate', 'LicensePlate', 'plate', 'Plate',
    -- AzeMP masinlarindan elave olunanlar
    '901',
    'sonata_plate',
    'plates1',
    'ext_plate330I',
    'EXT_PLATE_plastic',
    'Plates',
    'plaka',
    'formacar_logo_Diffuse',
    'azemp',
    'EXT_PLATE_plastic.001',
    'PlakaMain',
    'nomer',
    'plate1',
    'EXT_PLATE_LICENSE',
    'Material #235',
    'PLATE_F',
    'plates',
    -- 'YENI_MATERIAL_ADI',
  },
  -- Tekstur fayl adlari (meselen 'plate.dds'). Material adi ferqli olan masinlar ucun.
  textureNames = {
    -- 'plate.dds',
    -- 'license_plate_d.dds',
  },
  -- Material/tekstur ile tapilmasa, mesh adina gore (son care)
  meshNames = { 'license_plate*', 'License_Plate*', 'plate*', '*plate*' },
  -- Plaka shaderinde diffuse / normal slot adlari (bezi masinlarda ferqli ola biler)
  diffuseSlots = { 'txDiffuse' },
  normalSlots  = { 'txNormal' },

  -- Font: .ttf dosyasini PlateText/fonts/ icine koy
  fontFamily = 'DIN 1451 Std',            -- fontun ICINDEKI aile adi (dosyadan okundu)
  fontFolder = './fonts',
  useGlyphs  = true,   -- true: DIN harfleri glyphs/ klasorundeki resimlerden cizilir (font yuklemeye gerek yok)
  fontFile   = 'DINMittelschriftStd.ttf', -- fonts/ icindeki dosya adi
  bold       = false,
  textColor  = rgbm(0.02, 0.02, 0.02, 1),

  -- Yazi yerlesimi (referans plakadan olculdu, plaka genisligi/yuksekligine oran)
  boxLeft   = 0.184,   -- yazi alani sol kenar
  boxRight  = 0.940,   -- yazi alani sag kenar
  capHeight = 0.700,   -- buyuk harf yuksekligi / plaka yuksekligi (gercek plakadan olculdu)
  glyphXScale = 0.94,  -- butun herf/reqemleri yatayda daraldir (1.0 = eski gorunus). Gercek plaka daha dar
  spaceWidth  = 0.21,  -- sozler arasi bosluq (em). Boyutdukce '10 HG 500' arasi acilir
  fontCapRatio = 0.712, -- fontun buyuk harf yuksekligi / font boyutu (dosyadan olculdu)
  fontAscent   = nil,   -- nil = otomatik (olculen satir yuksekliginden bulunur). Elle: 0.712 / 0.812 / 0.938
  yShift    = 0.0,     -- yazi yukari/asagi kayiyorsa ayarla (piksel, + = asagi)

  canvasSize = vec2(1040, 220),           -- 520x110 plaka orani

  -- Sabit arka plan: PlateText/ klasorune koyacagin resim (png). Yoksa beyaz kullanilir.
  background = 'plate_bg.png',

  -- Normal map (yazidan otomatik uretilir)
  normalMap      = true,
  normalStrength = 5.0,    -- kabartma siddeti
  normalSpread   = 1.5,    -- kenar yumusakligi (piksel)
  normalFlipX    = true,   -- kabartma yonu: ikisi de true = yazi disari kabarik
  normalFlipY    = true,   -- sadece isik ust/alt ters geliyorsa bunu false yap

  -- Herflerin eni (1.0 = orijinal). T herfine toxunulmur. Reqemler deyismir.
  letterWidth = 0.92,

  -- O herfinin eni (0 reqemine nisbeten; 1.0 = 0 ile eyni)
  oWidth = 1.05,

  maxChars    = 12,
  resendEvery = 10,        -- sn
  defaultText = 'AZEMP',
}
-- ============================================================

local store = ac.storage('plateText', CONFIG.defaultText)
local myText = store:get()
local inputText = myText

local texts = {}     -- [carIndex] = yazi
local diffuse = {}   -- [carIndex] = ExtraCanvas
local normals = {}   -- [carIndex] = ExtraCanvas
local applied = {}   -- [carIndex] = uygulanan yazi

local SZ = CONFIG.canvasSize
local heightCanvas = ui.ExtraCanvas(SZ, 4)
local bgPath = asset(CONFIG.background)

-- Font (ilk cizimde, UI baglami hazirken secilir)
local font = nil
local fontStatus = 'secilmedi'
local fontReady = false

local function measureWith(f)
  local ok, w = pcall(function()
    ui.pushDWriteFont(f)
    local x = ui.measureDWriteText('77 ZL 077 WMiQ', 100).x
    ui.popDWriteFont()
    return x
  end)
  if not ok then ac.log('PlateText: olcum hatasi: ' .. tostring(w)) end
  return ok and w or nil
end

local function ensureFont()
  if fontReady then return end
  fontReady = true
  local fam, folder, file = CONFIG.fontFamily, CONFIG.fontFolder, CONFIG.fontFile
  local abs = './fonts'
  local candidates = {
    { 'nesne klasor',        function() return ui.DWriteFont(fam, folder) end },
    { 'nesne klasor+dosya',  function() return ui.DWriteFont(fam, folder .. '/' .. file) end },
    { 'nesne tam yol',       function() return ui.DWriteFont(fam, abs) end },
    { 'nesne tam yol+dosya', function() return ui.DWriteFont(fam, abs .. '/' .. file) end },
    { 'yazi ./fonts',        function() return fam .. ':./fonts' end },
    { 'yazi \\fonts',        function() return fam .. ':\\fonts' end },
    { 'yazi tam yol',        function() return fam .. ':' .. abs end },
  }
  local okRef, ref = pcall(function() return ui.DWriteFont('NoSuchFontXYZ', folder) end)
  local refW = okRef and measureWith(ref) or measureWith('NoSuchFontXYZ')
  ac.log('PlateText: font dizini = ' .. abs .. ' | varsayilan font genisligi = ' .. tostring(refW))

  local firstOk, firstName = nil, nil
  for _, c in ipairs(candidates) do
    local ok, f = pcall(c[2])
    if ok and f then
      local w = measureWith(f)
      ac.log('PlateText: font denemesi "' .. c[1] .. '" genislik=' .. tostring(w))
      if not firstOk then firstOk, firstName = f, c[1] end
      if w and refW and math.abs(w - refW) > 0.5 then
        font = f
        fontStatus = 'yuklendi (' .. c[1] .. ')'
        break
      end
    else
      ac.log('PlateText: font denemesi "' .. c[1] .. '" HATA: ' .. tostring(f))
    end
  end

  if not font and firstOk and (refW == nil) then
    -- olcum yapilamadi: dogrulayamiyoruz, ilk adayi kullan
    font = firstOk
    fontStatus = 'dogrulanamadi (' .. firstName .. ')'
  end
  if font and CONFIG.bold and type(font) ~= 'string' then
    pcall(function() font = font:weight(ui.DWriteFont.Weight.Bold) end)
  end
  if not font then
    fontStatus = 'YUKLENEMEDI (Arial)'
    ac.log('PlateText: font yuklenemedi. Dosya: fonts/' .. file .. ' | aile adi: "' .. fam .. '"')
  end
end

local function pushFont()
  ensureFont()
  if font then ui.pushDWriteFont(font) else ui.pushDWriteFont('Arial') end
end

local function drawBackground()
  local ok = pcall(function()
    local ready = true
    if ui.isImageReady then ready = ui.isImageReady(bgPath) end
    if ready then
      ui.drawImage(bgPath, vec2(0, 0), SZ)
    else
      ui.drawRectFilled(vec2(0, 0), SZ, rgbm.colors.white)
    end
  end)
  if not ok then ui.drawRectFilled(vec2(0, 0), SZ, rgbm.colors.white) end
end

-- ===== Otomatik uretildi: DIN 1451 Std glyph olculeri (em biriminde) =====
local GLYPH_ASC, GLYPH_DESC, GLYPH_CAP = 0.950, 0.200, 0.712
local GLYPH_M = {  -- [kod] = {ilerleme, sol bosluk, sag bosluk, resim genisligi}
  [48]={0.4800,0.0380,0.0380,0.5300},
  [49]={0.4800,0.0930,0.1840,0.5300},
  [50]={0.4800,0.0320,0.0420,0.5300},
  [51]={0.4800,0.0130,0.0490,0.5300},
  [52]={0.4800,0.0120,0.0120,0.5300},
  [53]={0.4800,0.0370,0.0370,0.5300},
  [54]={0.4800,0.0250,0.0225,0.5300},
  [55]={0.4800,0.0510,0.0240,0.5300},
  [56]={0.4800,0.0230,0.0230,0.5300},
  [57]={0.4800,0.0250,0.0250,0.5300},
  [65]={0.6100,0.0010,0.0010,0.6600},
  [66]={0.6100,0.0750,0.0370,0.6600},
  [67]={0.5560,0.0510,0.0010,0.6050},
  [68]={0.6300,0.0750,0.0510,0.6800},
  [69]={0.5560,0.0750,0.0260,0.6050},
  [70]={0.5370,0.0750,0.0070,0.5875},
  [71]={0.6100,0.0510,0.0510,0.6600},
  [72]={0.6480,0.0750,0.0750,0.6975},
  [73]={0.2580,0.0750,0.0750,0.3075},
  [74]={0.4810,0.0010,0.0670,0.5300},
  [75]={0.6300,0.0750,0.0000,0.6800},
  [76]={0.5560,0.0750,0.0260,0.6050},
  [77]={0.7580,0.0750,0.0750,0.8075},
  [78]={0.6840,0.0750,0.0750,0.7350},
  [79]={0.6100,0.0510,0.0510,0.6600},
  [80]={0.5930,0.0750,0.0230,0.6425},
  [81]={0.6100,0.0510,-0.0170,0.6600},
  [82]={0.6100,0.0750,0.0140,0.6600},
  [83]={0.5740,0.0130,0.0390,0.6250},
  [84]={0.5000,0.0450,0.0425,0.5500},
  [85]={0.6300,0.0620,0.0620,0.6800},
  [86]={0.5560,0.0010,0.0010,0.6050},
  [87]={0.8320,0.0110,0.0110,0.8825},
  [88]={0.5360,-0.0100,-0.0100,0.5850},
  [89]={0.5000,-0.0150,-0.0150,0.5500},
  [90]={0.5190,0.0320,0.0320,0.5700},
  [45]={0.4070,0.0900,0.0870,0.4575},
  [46]={0.2400,0.0690,0.0690,0.2900},
}
-- O herfi = 0 reqemi (eyni sekil ve olcu)
GLYPH_M[79] = GLYPH_M[48]
local GLYPH_K = {
  ['AC']=-0.0180,
  ['AG']=-0.0180,
  ['AO']=-0.0180,
  ['AQ']=-0.0180,
  ['AT']=-0.0740,
  ['AU']=-0.0180,
  ['AV']=-0.0550,
  ['AW']=-0.0370,
  ['AY']=-0.0740,
  ['DA']=-0.0180,
  ['DV']=-0.0120,
  ['DY']=-0.0240,
  ['FA']=-0.0550,
  ['F.']=-0.1290,
  ['J.']=-0.0180,
  ['KO']=-0.0240,
  ['LT']=-0.1110,
  ['LV']=-0.1110,
  ['LW']=-0.0740,
  ['LY']=-0.1290,
  ['OA']=-0.0180,
  ['OT']=-0.0180,
  ['OV']=-0.0250,
  ['OW']=-0.0180,
  ['OX']=-0.0120,
  ['OY']=-0.0300,
  ['O.']=-0.0250,
  ['PA']=-0.0740,
  ['P.']=-0.1290,
  ['QU']=-0.0060,
  ['RT']=-0.0180,
  ['RV']=-0.0180,
  ['RW']=-0.0180,
  ['RY']=-0.0300,
  ['TA']=-0.0740,
  ['TO']=-0.0180,
  ['T-']=-0.1290,
  ['T.']=-0.1110,
  ['UA']=-0.0250,
  ['U.']=-0.0250,
  ['VA']=-0.0550,
  ['VG']=-0.0180,
  ['VO']=-0.0180,
  ['V-']=-0.0550,
  ['V.']=-0.1290,
  ['WA']=-0.0370,
  ['W-']=-0.0180,
  ['W.']=-0.0740,
  ['YA']=-0.0740,
  ['YO']=-0.0250,
  ['Y-']=-0.1110,
  ['Y.']=-0.1110,
}

local GLYPH_PAD = 10 / 400   -- uretimdeki kenar boslugu (em)
local glyphOk = nil
local function useGlyphs()
  if glyphOk == nil then
    glyphOk = false
    if CONFIG.useGlyphs then
      glyphOk = true
    end
    if glyphOk then fontStatus = 'DIN glyph resimleri' end
    ac.log('PlateText: glyph modu = ' .. tostring(glyphOk) .. ' | url = ' .. ASSET_BASE)
  end
  return glyphOk
end

-- Yazıyı DIN glyph resimleriyle cizer (font yuklemeye gerek yok)
local function widthOf(c)
  local xs = CONFIG.glyphXScale or 1
  if c == 79 then return CONFIG.oWidth * xs end   -- O: 0 reqeminden azca eni
  if c >= 65 and c <= 90 and c ~= 84 then return CONFIG.letterWidth * xs end   -- A-Z, T xaric
  return xs
end

local function drawGlyphText(text, color)
  local codes, pos, x = {}, {}, 0
  local prev = nil
  for i = 1, #text do
    local c = text:byte(i)
    local m = GLYPH_M[c]
    if m or c == 32 then
      if prev and m then
        x = x + (GLYPH_K[string.char(prev) .. string.char(c)] or 0) * (widthOf(prev) + widthOf(c)) / 2
      end
      codes[#codes + 1] = c
      pos[#codes] = x
      x = x + (m and m[1] * widthOf(c) or CONFIG.spaceWidth * (CONFIG.glyphXScale or 1))   -- bosluk
      prev = c
    end
  end
  if #codes == 0 then return end
  local first = GLYPH_M[codes[1]]; local last = GLYPH_M[codes[#codes]]
  local inkL = first and first[2] * widthOf(codes[1]) or 0
  local inkR = x - (last and last[3] * widthOf(codes[#codes]) or 0)
  local inkW = inkR - inkL

  local size = (SZ.y * CONFIG.capHeight) / GLYPH_CAP
  local boxW = SZ.x * (CONFIG.boxRight - CONFIG.boxLeft)
  if inkW * size > boxW then size = boxW / inkW end
  local cx = SZ.x * (CONFIG.boxLeft + CONFIG.boxRight) / 2
  local x0 = cx - inkW * size / 2 - inkL * size
  local baseY = SZ.y / 2 + CONFIG.yShift + GLYPH_CAP * size / 2

  for i, c in ipairs(codes) do
    local m = GLYPH_M[c]
    if m then
      local sx = widthOf(c)
      local gx = x0 + pos[i] * size - GLYPH_PAD * size * sx
      ui.drawImage(asset('g' .. (c == 79 and 48 or c) .. '.png'),
        vec2(gx, baseY - GLYPH_ASC * size),
        vec2(gx + m[4] * size * sx, baseY + GLYPH_DESC * size), color)
    end
  end
end

local loggedLH = false
local function drawText(text, color)
  if useGlyphs() then drawGlyphText(text, color) return end
  pushFont()
  -- boyut: buyuk harf yuksekligi referans plakayla ayni olsun
  local size = (SZ.y * CONFIG.capHeight) / CONFIG.fontCapRatio
  local tsize = ui.measureDWriteText(text, size)
  local boxW = SZ.x * (CONFIG.boxRight - CONFIG.boxLeft)
  if tsize.x > boxW then          -- uzun yazi alana sigsin (yukseklik de kuculur)
    size = size * boxW / tsize.x
    tsize = ui.measureDWriteText(text, size)
  end
  local cx = SZ.x * (CONFIG.boxLeft + CONFIG.boxRight) / 2
  local cy = SZ.y / 2 + CONFIG.yShift
  -- buyuk harflerin ortasi cy'ye gelsin (satir kutusunun ortasina degil)
  local asc = CONFIG.fontAscent
  if not asc then
    local lh = tsize.y / size
    if math.abs(lh - 1.188) < 0.03 then asc = 0.938      -- Windows metrikleri
    elseif math.abs(lh - 1.2) < 0.03 then asc = 0.812    -- hhea + satir boslugu
    elseif math.abs(lh - 1.0) < 0.03 then asc = 0.712    -- hhea
    else asc = lh * 0.79 end
    if not loggedLH then
      loggedLH = true
      ac.log('PlateText: satir yuksekligi orani = ' .. string.format('%.3f', lh) .. ' -> ascent = ' .. string.format('%.3f', asc))
    end
  end
  local top = cy - (asc - CONFIG.fontCapRatio / 2) * size
  ui.dwriteDrawText(text, size, vec2(cx - tsize.x / 2, top), color)
  ui.popDWriteFont()
end

local function drawDiffuse(canvas, text)
  canvas:update(function()
    drawBackground()
    drawText(text, CONFIG.textColor)
  end)
end

local NORMAL_SHADER = [[
float hgt(float2 uv) { return txHeight.Sample(samLinear, uv).r; }
float4 main(PS_IN pin) {
  float2 s = gTexel * gSpread;
  float tl = hgt(pin.Tex + float2(-s.x, -s.y));
  float tc = hgt(pin.Tex + float2( 0.0, -s.y));
  float tr = hgt(pin.Tex + float2( s.x, -s.y));
  float ml = hgt(pin.Tex + float2(-s.x,  0.0));
  float mr = hgt(pin.Tex + float2( s.x,  0.0));
  float bl = hgt(pin.Tex + float2(-s.x,  s.y));
  float bc = hgt(pin.Tex + float2( 0.0,  s.y));
  float br = hgt(pin.Tex + float2( s.x,  s.y));
  float dx = (tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl);
  float dy = (bl + 2.0 * bc + br) - (tl + 2.0 * tc + tr);
  float3 n = normalize(float3(-dx * gStrength * gFlipX, -dy * gStrength * gFlipY, 1.0));
  return float4(n * 0.5 + 0.5, 1.0);
}
]]

local function drawNormal(canvas, text)
  heightCanvas:update(function()
    ui.drawRectFilled(vec2(0, 0), SZ, rgbm(0, 0, 0, 1))
    drawText(text, rgbm(1, 1, 1, 1))
  end)
  canvas:updateWithShader({
    p1 = vec2(0, 0), p2 = SZ,
    textures = { txHeight = heightCanvas },
    values = {
      gTexel = vec2(1 / SZ.x, 1 / SZ.y),
      gSpread = CONFIG.normalSpread,
      gStrength = CONFIG.normalStrength,
      gFlipX = CONFIG.normalFlipX and -1 or 1,
      gFlipY = CONFIG.normalFlipY and -1 or 1,
    },
    shader = NORMAL_SHADER,
  })
end

-- Butun uygun meshleri toplayir (bir masinda bir nece material/tekstur ola biler)
local function findPlateMeshes(i)
  local root = ac.findNodes('carRoot:' .. i)
  local found = {}
  local function try(query, label)
    local ok, meshes = pcall(function() return root:findMeshes(query) end)
    if ok and meshes and #meshes > 0 then
      found[#found + 1] = meshes
      ac.log('PlateText: car ' .. i .. ' ' .. label .. ' "' .. query .. '" -> ' .. #meshes .. ' mesh')
    end
  end
  for _, name in ipairs(CONFIG.materialNames) do try('material:' .. name, 'material') end
  for _, name in ipairs(CONFIG.textureNames)  do try('texture:' .. name, 'texture') end
  if #found == 0 then
    for _, name in ipairs(CONFIG.meshNames) do
      try(name, 'mesh')
      if #found > 0 then break end
    end
  end
  if #found == 0 then
    ac.log('PlateText: car ' .. i .. ' plaka bulunamadi')
    return nil
  end
  return found
end

local function setSlots(list, slots, tex)
  for _, meshes in ipairs(list) do
    for _, slot in ipairs(slots) do meshes:setMaterialTexture(slot, tex) end
  end
end

local function applyToCar(i)
  local text = texts[i]
  if not text or text == '' or applied[i] == text then return end

  local ok, err = pcall(function()
    local list = findPlateMeshes(i)
    if not list then return end

    if not diffuse[i] then diffuse[i] = ui.ExtraCanvas(SZ, 4) end
    drawDiffuse(diffuse[i], text)
    setSlots(list, CONFIG.diffuseSlots, diffuse[i])
    applied[i] = text

    if CONFIG.normalMap then
      local ok2, err2 = pcall(function()
        if not normals[i] then normals[i] = ui.ExtraCanvas(SZ, 4) end
        drawNormal(normals[i], text)
        setSlots(list, CONFIG.normalSlots, normals[i])
      end)
      if not ok2 then ac.log('PlateText NORMAL HATA: ' .. tostring(err2)) end
    end
  end)
  if not ok then ac.log('PlateText HATA: ' .. tostring(err)) end
end

-- Online sync
local plateEvent = ac.OnlineEvent({
  text = ac.StructItem.string(16)
}, function(sender, data)
  if sender == nil then return end
  texts[sender.index] = data.text
  applied[sender.index] = nil
  applyToCar(sender.index)
end)

-- Onizleme
local previewD = ui.ExtraCanvas(SZ, 4)
local function refreshPreview(text)
  drawDiffuse(previewD, text)
end

local clockT = 0          -- kendi saatimiz
local lastApplied = -100
local function setMyPlate(text)
  text = string.upper(text):sub(1, CONFIG.maxChars)
  lastApplied = clockT
  myText = text
  store:set(text)
  texts[0] = text
  applied[0] = nil
  applyToCar(0)
  refreshPreview(text)
  plateEvent({ text = text })
end

local bootError = nil
do
  local okB, errB = pcall(setMyPlate, myText)
  if not okB then
    bootError = tostring(errB)
    ac.log('PlateText BOOT HATA: ' .. bootError)
  end
  lastApplied = -100
end
ac.log('PlateText: init bitti, bootError = ' .. tostring(bootError))

-- Internetden gelen sekiller gec yuklene biler: hazir olana qeder plakalari yeniden cizir
local assetList = { bgPath }
for code, _ in pairs(GLYPH_M) do assetList[#assetList + 1] = asset('g' .. (code == 79 and 48 or code) .. '.png') end
local assetsDone, assetTimer, assetAge = false, 0, 0
local function allAssetsReady()
  if not ui.isImageReady then return assetAge > 20 end   -- funksiya yoxdursa 20 sn gozle
  for _, p in ipairs(assetList) do
    local ok, r = pcall(ui.isImageReady, p)
    if ok and not r then return false end
  end
  return true
end

local timer, retry = 0, 0
local function updateBody(dt)
  clockT = clockT + dt
  timer = timer + dt
  retry = retry + dt
  if timer > CONFIG.resendEvery then
    timer = 0
    plateEvent({ text = myText })
  end
  if not assetsDone then
    assetAge = assetAge + dt
    assetTimer = assetTimer + dt
    if assetTimer > 1.5 then
      assetTimer = 0
      if allAssetsReady() or assetAge > 60 then
        assetsDone = true
        ac.log('PlateText: sekiller hazirdir')
      end
      for k in pairs(applied) do applied[k] = nil end   -- yeniden ciz
      pcall(refreshPreview, inputText)
    end
  end
  if retry > 2 then   -- araba/mesh gec yuklenirse tekrar dene
    retry = 0
    for i, t in pairs(texts) do
      if applied[i] ~= t then applyToCar(i) end
    end
  end
end

local updErr = false
function script.update(dt)
  local ok, err = pcall(updateBody, dt)
  if not ok and not updErr then
    updErr = true
    ac.log('PlateText UPDATE HATA: ' .. tostring(err))
  end
end

-- ====================== ARAYUZ (sabit olcu, tek tema) ======================
local UI_SCREEN = true

local T = {
  bg = { 10 / 255, 7 / 255, 16 / 255, 1 },
  card = { 28 / 255, 18 / 255, 42 / 255, 0.6 },
  line = { 192 / 255, 132 / 255, 252 / 255, 0.20 },
  text = { 246 / 255, 242 / 255, 252 / 255, 1 },
  muted = { 160 / 255, 146 / 255, 184 / 255, 1 },
  accent = { 147 / 255, 51 / 255, 234 / 255, 1 },    -- mor
  accent2 = { 217 / 255, 70 / 255, 239 / 255, 1 },   -- magenta
}
T.ok = T.accent2

local function K(t, a) return rgbm(t[1], t[2], t[3], t[4] * (a or 1)) end
local function Kmix(t1, t2, k)
  return rgbm(t1[1] + (t2[1] - t1[1]) * k, t1[2] + (t2[2] - t1[2]) * k,
              t1[3] + (t2[3] - t1[3]) * k, t1[4] + (t2[4] - t1[4]) * k)
end

local F_REG, F_SEMI = 'Segoe UI', 'Segoe UI;Weight=SemiBold'

-- Yigin takibi: xeta olarsa temizlensin
local depth = { var = 0, col = 0, font = 0, ind = {} }
local function pushVar(a, b) ui.pushStyleVar(a, b); depth.var = depth.var + 1 end
local function popVar(n) n = n or 1; ui.popStyleVar(n); depth.var = depth.var - n end
local function pushCol(a, b) ui.pushStyleColor(a, b); depth.col = depth.col + 1 end
local function popCol(n) n = n or 1; ui.popStyleColor(n); depth.col = depth.col - n end
local function indent(w) ui.indent(w); depth.ind[#depth.ind + 1] = w end
local function unindent(w) ui.unindent(w); depth.ind[#depth.ind] = nil end
local function unwind()
  if depth.var > 0 then pcall(ui.popStyleVar, depth.var) end
  if depth.col > 0 then pcall(ui.popStyleColor, depth.col) end
  while depth.font > 0 do pcall(ui.popDWriteFont); depth.font = depth.font - 1 end
  for k = #depth.ind, 1, -1 do pcall(ui.unindent, depth.ind[k]) end
  depth.var, depth.col, depth.font, depth.ind = 0, 0, 0, {}
end

local anim = {}
local function smooth(id, target, dt, speed)
  local v = anim[id]
  if v == nil then v = target end
  v = v + (target - v) * math.min(1, dt * (speed or 16))
  anim[id] = v
  return v
end

local curOffset = vec2(0, 0)
local function rawCursor()
  if ui.getCursor then return ui.getCursor() end
  return vec2(ui.getCursorX(), ui.getCursorY())
end
local function cur() return rawCursor() + curOffset end
local function availX()
  if ui.availableSpaceX then return ui.availableSpaceX() end
  if ui.availableSpace then return ui.availableSpace().x end
  return ui.windowSize().x - 24
end
local function gap(h) ui.dummy(vec2(1, h)) end

local function drawLabel(str, size, pos, col, font)
  ui.pushDWriteFont(font or F_REG); depth.font = depth.font + 1
  ui.dwriteDrawText(str, size, pos, col)
  ui.popDWriteFont(); depth.font = depth.font - 1
end
local function labelSize(str, size, font)
  ui.pushDWriteFont(font or F_REG); depth.font = depth.font + 1
  local sz = ui.measureDWriteText(str, size)
  ui.popDWriteFont(); depth.font = depth.font - 1
  return sz
end

local function drawRoundedImage(src, p1, p2, r)
  local ok = pcall(ui.drawImageRounded, src, p1, p2, rgbm(1, 1, 1, 1), vec2(0, 0), vec2(1, 1), r)
  if not ok then ui.drawImage(src, p1, p2) end
end

local function sanitize(str)
  str = string.upper(str or ''):gsub('[^A-Z0-9 %-%.]', '')
  return str:sub(1, CONFIG.maxChars)
end

local function primaryButton(id, label, size, dt)
  local p = cur()
  local clicked = ui.invisibleButton(id, size)
  local k = smooth(id, ui.itemHovered() and 1 or 0, dt)
  local press = smooth(id .. 'p', ui.itemActive() and 1 or 0, dt)
  ui.drawRectFilled(p, p + size, Kmix(T.accent, T.accent2, k), 8)
  if press > 0.01 then ui.drawRectFilled(p, p + size, rgbm(0, 0, 0, 0.18 * press), 8) end
  local sz = labelSize(label, 14, F_SEMI)
  drawLabel(label, 14, p + (size - sz) / 2, rgbm(1, 1, 1, 1), F_SEMI)
  return clicked
end

local function plainButton(id, label, size, dt)
  local p = cur()
  local clicked = ui.invisibleButton(id, size)
  local k = smooth(id, ui.itemHovered() and 1 or 0, dt)
  if k > 0.01 then ui.drawRectFilled(p, p + size, rgbm(1, 1, 1, 0.05 * k), 8) end
  local sz = labelSize(label, 13, F_REG)
  drawLabel(label, 13, p + (size - sz) / 2, Kmix(T.muted, T.text, k), F_REG)
  return clicked
end

local function windowMainPro(dt)
  dt = math.min(dt or 0.016, 0.05)
  pushVar(ui.StyleVar.ItemSpacing, vec2(0, 0))

  -- koordinat kalibrasyonu
  local p0 = rawCursor()
  ui.dummy(vec2(1, 1))
  curOffset = ui.itemRectMin() - p0

  -- fon
  -- Seffaf + blur fon: pencere konumuna baglanmir (pencere kenarlarinda kesilir), surusdurende geride qalmir
  local im = ui.itemRectMin()
  local big = vec2(4000, 4000)
  local okB = pcall(ui.beginBlurredBackground)
  pcall(ui.drawRectFilled, im - big, im + big, K(T.bg, 0.25))
  if okB then pcall(ui.endBlurredBackground) end

  local M = 16
  indent(M)
  local W = availX() - M

  -- basliq
  gap(16)
  local hp = cur()
  local lw = 150
  local lh = lw * 176 / 640
  local lx = hp.x + (W - lw) / 2
  pcall(ui.drawImage, asset('logo.png'), vec2(lx, hp.y), vec2(lx + lw, hp.y + lh), rgbm(1, 1, 1, 1))
  ui.dummy(vec2(W, lh + 8))

  -- Onizleme (yalniz plaka)
  gap(6)
  local pad = 10
  local pw = W - pad * 2
  local ph = pw * SZ.y / SZ.x
  local cardH = pad * 2 + ph
  local cp = cur()
  ui.drawRectFilled(cp, cp + vec2(W, cardH), K(T.card), 10)
  ui.drawRect(cp, cp + vec2(W, cardH), K(T.line), 10)
  drawRoundedImage(previewD, cp + vec2(pad, pad), cp + vec2(pad + pw, pad + ph), 5)
  ui.dummy(vec2(W, cardH))

  -- Yazi sahesi
  gap(20)
  local lp = cur()
  drawLabel('MƏTN', 11, lp + vec2(2, 0), K(T.muted), F_SEMI)
  local cnt = #inputText .. ' / ' .. CONFIG.maxChars
  local cs = labelSize(cnt, 11, F_REG)
  drawLabel(cnt, 11, lp + vec2(W - cs.x - 2, 0), K(T.muted), F_REG)
  ui.dummy(vec2(W, 16))
  gap(6)

  ui.setNextItemWidth(W)
  pushCol(ui.StyleColor.FrameBg, K(T.card))
  pushCol(ui.StyleColor.FrameBgHovered, K(T.card))
  pushCol(ui.StyleColor.FrameBgActive, K(T.card))
  pushCol(ui.StyleColor.Text, K(T.text))
  pushVar(ui.StyleVar.FrameRounding, 8)
  pushVar(ui.StyleVar.FramePadding, vec2(12, 10))
  local newText, changed, entered = ui.inputText('##plate', inputText)
  popVar(2)
  popCol(4)
  local imin, imax = ui.itemRectMin(), ui.itemRectMax()
  local focus = smooth('inputFocus', ui.itemActive() and 1 or 0, dt)
  ui.drawRect(imin, imax, Kmix(T.line, T.accent2, focus), 8)
  if inputText == '' then
    local phs = labelSize('Məs: 77 ZL 077', 14, F_REG)
    drawLabel('Məs: 77 ZL 077', 14, imin + vec2(13, ((imax.y - imin.y) - phs.y) / 2), K(T.muted, 0.7), F_REG)
  end
  if changed then
    inputText = sanitize(newText)
    refreshPreview(inputText)
  end

  -- Duymeler
  gap(16)
  local applyClicked = primaryButton('apply', 'Tətbiq et', vec2(W, 42), dt)
  gap(6)
  local resetClicked = plainButton('reset', 'Standart', vec2(W, 30), dt)
  if applyClicked or entered then
    inputText = sanitize(inputText)
    setMyPlate(inputText)
  end
  if resetClicked then
    inputText = CONFIG.defaultText
    refreshPreview(inputText)
    setMyPlate(inputText)
  end

  -- Tesdiq gostericisi (yalniz tetbiqden sonra)
  gap(6)
  local tp = cur()
  local age = clockT - lastApplied
  if age < 2.6 then
    local a = math.min(1, (2.6 - age) / 0.5)
    local tw = labelSize('Tətbiq olundu', 12, F_SEMI).x
    local x0 = tp.x + (W - tw - 18) / 2
    ui.drawLine(vec2(x0, tp.y + 10), vec2(x0 + 3, tp.y + 13), K(T.ok, a), 2)
    ui.drawLine(vec2(x0 + 3, tp.y + 13), vec2(x0 + 9, tp.y + 6), K(T.ok, a), 2)
    drawLabel('Tətbiq olundu', 12, vec2(x0 + 18, tp.y + 2), K(T.ok, a), F_SEMI)
  end
  ui.dummy(vec2(W, 22))

  unindent(M)
  popVar()
end

-- ====================== Etibarli pencere: xeta olarsa sade rejim ======================
local uiError = nil

local function windowMainSimple(dt)
  if uiError then
    ui.text('İnterfeys xətası. Ətraflı: CSP log faylı.')
    if ui.button('Yenidən cəhd et') then uiError = nil end
  end
  ui.image(previewD, vec2(340, 72))
  local newText, changed = ui.inputText('Mətn', inputText)
  if changed then
    inputText = sanitize(newText)
    refreshPreview(inputText)
  end
  if ui.button('Tətbiq et') then setMyPlate(inputText) end
end

function windowMain(dt)
  if not uiError then
    local ok, err = pcall(windowMainPro, dt)
    if ok then return end
    uiError = tostring(err)
    ac.log('PlateText UI HATA: ' .. uiError)
    unwind()
  end
  windowMainSimple(dt)
end


-- ====================== SERVER-SIDE: duyme ile pencere ======================
local WINDOW_SIZE = vec2(380, 380)
local windowOpen = false

local toggleBtn = nil
pcall(function()
  toggleBtn = ac.ControlButton('__PLATETEXT_TOGGLE', { keyboard = { key = TOGGLE_KEY } })
end)

local function togglePressed()
  if toggleBtn then
    local ok, r = pcall(function() return toggleBtn:pressed() end)
    if ok then return r end
  end
  local ok, r = pcall(ui.keyboardButtonPressed, TOGGLE_KEY, false)
  return ok and r
end

function script.drawUI(dt)
  if togglePressed() then windowOpen = not windowOpen end
  if windowOpen and ui.keyboardButtonPressed(ui.KeyIndex.Escape, false) then windowOpen = false end
  if not windowOpen then return end

  local scr = ui.windowSize()
  local pos = vec2((scr.x - WINDOW_SIZE.x) / 2, (scr.y - WINDOW_SIZE.y) / 2)
  ui.transparentWindow('PlateTextWindow', pos, WINDOW_SIZE, true, true, function()
    windowMain(dt)
  end)
end
