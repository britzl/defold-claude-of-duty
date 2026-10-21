-- Browsers can send compatibility mouse events after touchend in addition to
-- Defold's touch-sourced actions. Filter them before they reach the canvas.
local M={}
function M.install()
    local system=sys.get_sys_info().system_name
    M.native_touch=system=="Android" or system=="iPhone OS"
    if not html5 then return end
    html5.run([=[
        (function () {
            if (window.__codTouchMouseGuard) return;
            window.__codTouchMouseGuard = true;
            window.__codLastTouch = -Infinity;
            window.__codTouchCount = 0;
            const touched = event => {
                window.__codLastTouch = performance.now();
                window.__codTouchCount = event.touches.length;
            };
            for (const type of ['touchstart', 'touchmove', 'touchend', 'touchcancel'])
                window.addEventListener(type, touched, {capture:true, passive:true});
            window.addEventListener('pointerdown', event => {
                if (event.pointerType === 'mouse') window.__codLastTouch = -Infinity;
            }, {capture:true, passive:true});
            for (const type of ['mousedown', 'mouseup', 'mousemove', 'click', 'dblclick']) {
                window.addEventListener(type, function (event) {
                    if (event.target !== Module.canvas) return;
                    const caps = event.sourceCapabilities;
                    const fromTouch = caps ? caps.firesTouchEvents : performance.now() - window.__codLastTouch < 700;
                    if (fromTouch) { event.stopImmediatePropagation(); event.preventDefault(); }
                    else if (caps && !caps.firesTouchEvents) window.__codLastTouch = -Infinity;
                }, {capture:true, passive:false});
            }
            Module.canvas.style.touchAction = 'none';
        })();
    ]=])
end
-- Release HTML5 engines predating action.source synthesize mouse input from
-- touch *inside* the engine, before the multi-touch callback. DOM timestamps
-- also cover that order, including the first press and the final release.
function M.compatibility_mouse()
    if M.native_touch then return true end
    return html5 and html5.run("(window.__codTouchCount > 0 || performance.now()-window.__codLastTouch < 700) ? '1' : '0'")=="1" or false
end
return M
