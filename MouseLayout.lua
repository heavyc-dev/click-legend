-------------------------------------------------------------------------------
--  ClickLegend - MouseLayout.lua
--  The pictures of a mouse for the "Mouse picture" layout of the legend, and
--  where their buttons are. Written by dev/make_mouse_layout.py from the art
--  in mouse-files/; change it there, not here.
--
--  For each picture:
--    texture    the image: white on clear, so that it can be tinted
--    size       the picture's own units across and down; every point below is
--               in these, from its top left, y downward
--    bounds     the drawn part: left, top, right, bottom. Outside it is clear
--    regions    per button: cx, cy the middle of it; calloutX, calloutY where
--               on its outer edge a line to its spell icons starts
--    keys       the key each region shows
--    left, right  regions whose icons go left and right of the picture, top
--               to bottom
--    wheel, wheelKeys  the wheel's region, and its three keys in the order
--               they are stacked
--    grid       a block of side buttons, by row from the top, left to right:
--               shown as one block of icons with a single line to it
-------------------------------------------------------------------------------
local _, ns = ...

ns.MOUSE_ORDER = { "a", "b", "c", "d" }
ns.MOUSE_LAYOUTS = {
    a = {
        name = "Rounded",
        texture = "Interface\\AddOns\\ClickLegend\\media\\mouse_a.png",
        size = 512,
        bounds = { 132, 49, 368, 466 },
        regions = {
            ["wheel"] = { cx = 256, cy = 139, calloutX = 256, calloutY = 94 },
            ["btn-left"] = { cx = 195, cy = 172, calloutX = 145, calloutY = 172 },
            ["btn-right"] = { cx = 317, cy = 172, calloutX = 367, calloutY = 172 },
            ["btn-side-back"] = { cx = 154, cy = 394, calloutX = 132, calloutY = 394 },
            ["btn-side-front"] = { cx = 154, cy = 320, calloutX = 132, calloutY = 320 },
        },
        keys = {
            BUTTON1 = "btn-left",
            BUTTON2 = "btn-right",
            BUTTON3 = "wheel",
            BUTTON4 = "btn-side-back",
            BUTTON5 = "btn-side-front",
            MOUSEWHEELDOWN = "wheel",
            MOUSEWHEELUP = "wheel",
        },
        left = { "btn-left", "btn-side-front", "btn-side-back" },
        right = { "btn-right" },
        wheel = "wheel",
        wheelKeys = { "BUTTON3", "MOUSEWHEELUP", "MOUSEWHEELDOWN" },
    },
    b = {
        name = "Angular",
        texture = "Interface\\AddOns\\ClickLegend\\media\\mouse_b.png",
        size = 512,
        bounds = { 132, 49, 368, 464 },
        regions = {
            ["wheel"] = { cx = 256, cy = 140, calloutX = 256, calloutY = 94 },
            ["btn-left"] = { cx = 196, cy = 169, calloutX = 146, calloutY = 169 },
            ["btn-right"] = { cx = 316, cy = 169, calloutX = 366, calloutY = 169 },
            ["btn-side-back"] = { cx = 155, cy = 400, calloutX = 132, calloutY = 400 },
            ["btn-side-front"] = { cx = 155, cy = 326, calloutX = 132, calloutY = 326 },
        },
        keys = {
            BUTTON1 = "btn-left",
            BUTTON2 = "btn-right",
            BUTTON3 = "wheel",
            BUTTON4 = "btn-side-back",
            BUTTON5 = "btn-side-front",
            MOUSEWHEELDOWN = "wheel",
            MOUSEWHEELUP = "wheel",
        },
        left = { "btn-left", "btn-side-front", "btn-side-back" },
        right = { "btn-right" },
        wheel = "wheel",
        wheelKeys = { "BUTTON3", "MOUSEWHEELUP", "MOUSEWHEELDOWN" },
    },
    c = {
        name = "Simple",
        texture = "Interface\\AddOns\\ClickLegend\\media\\mouse_c.png",
        size = 512,
        bounds = { 144, 50, 368, 464 },
        regions = {
            ["wheel"] = { cx = 256, cy = 142, calloutX = 256, calloutY = 106 },
            ["btn-left"] = { cx = 204, cy = 179, calloutX = 166, calloutY = 179 },
            ["btn-right"] = { cx = 308, cy = 179, calloutX = 346, calloutY = 179 },
            ["btn-side-back"] = { cx = 192, cy = 373, calloutX = 172, calloutY = 373 },
            ["btn-side-front"] = { cx = 192, cy = 305, calloutX = 172, calloutY = 305 },
        },
        keys = {
            BUTTON1 = "btn-left",
            BUTTON2 = "btn-right",
            BUTTON3 = "wheel",
            BUTTON4 = "btn-side-back",
            BUTTON5 = "btn-side-front",
            MOUSEWHEELDOWN = "wheel",
            MOUSEWHEELUP = "wheel",
        },
        left = { "btn-left", "btn-side-front", "btn-side-back" },
        right = { "btn-right" },
        wheel = "wheel",
        wheelKeys = { "BUTTON3", "MOUSEWHEELUP", "MOUSEWHEELDOWN" },
    },
    d = {
        name = "Twelve side buttons",
        texture = "Interface\\AddOns\\ClickLegend\\media\\mouse_d.png",
        size = 512,
        bounds = { 136, 56, 376, 463 },
        regions = {
            ["wheel"] = { cx = 256, cy = 127, calloutX = 256, calloutY = 86 },
            ["btn-left"] = { cx = 190, cy = 148, calloutX = 140, calloutY = 148 },
            ["btn-right"] = { cx = 322, cy = 148, calloutX = 372, calloutY = 148 },
            ["btn-side-1"] = { cx = 167, cy = 263, calloutX = 150, calloutY = 263 },
            ["btn-side-2"] = { cx = 209, cy = 263, calloutX = 192, calloutY = 263 },
            ["btn-side-3"] = { cx = 251, cy = 263, calloutX = 234, calloutY = 263 },
            ["btn-side-4"] = { cx = 167, cy = 305, calloutX = 150, calloutY = 305 },
            ["btn-side-5"] = { cx = 209, cy = 305, calloutX = 192, calloutY = 305 },
            ["btn-side-6"] = { cx = 251, cy = 305, calloutX = 234, calloutY = 305 },
            ["btn-side-7"] = { cx = 167, cy = 347, calloutX = 150, calloutY = 347 },
            ["btn-side-8"] = { cx = 209, cy = 347, calloutX = 192, calloutY = 347 },
            ["btn-side-9"] = { cx = 251, cy = 347, calloutX = 234, calloutY = 347 },
            ["btn-side-10"] = { cx = 167, cy = 389, calloutX = 150, calloutY = 389 },
            ["btn-side-11"] = { cx = 209, cy = 389, calloutX = 192, calloutY = 389 },
            ["btn-side-12"] = { cx = 251, cy = 389, calloutX = 234, calloutY = 389 },
        },
        keys = {
            BUTTON1 = "btn-left",
            BUTTON2 = "btn-right",
            BUTTON3 = "wheel",
            BUTTON4 = "btn-side-1",
            BUTTON5 = "btn-side-2",
            BUTTON6 = "btn-side-3",
            BUTTON7 = "btn-side-4",
            BUTTON8 = "btn-side-5",
            BUTTON9 = "btn-side-6",
            BUTTON10 = "btn-side-7",
            BUTTON11 = "btn-side-8",
            BUTTON12 = "btn-side-9",
            BUTTON13 = "btn-side-10",
            BUTTON14 = "btn-side-11",
            BUTTON15 = "btn-side-12",
            MOUSEWHEELDOWN = "wheel",
            MOUSEWHEELUP = "wheel",
        },
        left = { "btn-left" },
        right = { "btn-right" },
        wheel = "wheel",
        wheelKeys = { "BUTTON3", "MOUSEWHEELUP", "MOUSEWHEELDOWN" },
        grid = { columns = 3, regions = { "btn-side-1", "btn-side-2", "btn-side-3", "btn-side-4", "btn-side-5", "btn-side-6", "btn-side-7", "btn-side-8", "btn-side-9", "btn-side-10", "btn-side-11", "btn-side-12" } },
    },
}
