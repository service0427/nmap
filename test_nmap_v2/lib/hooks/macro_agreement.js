/* 
   Self-Triggering Macro Bot v11 (The Ultimate Solution)
   - Goal: ZERO delay, ZERO overhead, ZERO session conflict.
   - Strategy: Hook N-Log transmission + Coordinate Fallback for WebViews.
*/

Java.perform(function() {
    console.log("[Frida 🤖] 자가 트리거 매크로 v11 활성화 (이벤트 실시간 반응 + 좌표 폴백 모드)");

    var taskCompleted = false;

    // --- 1. View Traverser ---
    function findWebView(view) {
        if (view.getClass().getName().includes("WebView")) {
            return view;
        }
        if (view.instanceOf(Java.use("android.view.ViewGroup"))) {
            var group = Java.cast(view, Java.use("android.view.ViewGroup"));
            for (var i = 0; i < group.getChildCount(); i++) {
                var child = group.getChildAt(i);
                var found = findWebView(child);
                if (found) return found;
            }
        }
        return null;
    }

    // --- 2. Action Logic ---
    function executeAgreement(wv, attempt) {
        if (!attempt) attempt = 1;
        if (attempt > 8) {
            console.log("[Frida 🤖] 약관 동의 조작 시도 종료");
            return;
        }

        var location = Java.array('int', [0, 0]);
        wv.getLocationOnScreen(location);
        var wvX = location[0];
        var wvY = location[1];

        // Advanced discovery using XPath
        var jsPayload = "(function() { " +
            "  var results = []; " +
            "  function getCoords(el) { var r = el.getBoundingClientRect(); return {x: r.left, y: r.top, w: r.width, h: r.height}; } " +
            "  " +
            "  // 1. Find '필수' checkboxes via text label " +
            "  var it = document.evaluate(\"//*[contains(text(), '필수')]\", document, null, XPathResult.ANY_TYPE, null); " +
            "  var el = it.iterateNext(); " +
            "  while(el) { " +
            "    results.push({type: 'checkbox', coords: getCoords(el)}); " +
            "    el = it.iterateNext(); " +
            "  } " +
            "  " +
            "  // 2. Find '동의' button " +
            "  var it2 = document.evaluate(\"//button[contains(., '동의')] | //a[contains(., '동의')] | //div[@role='button' and contains(., '동의')]\", document, null, XPathResult.ANY_TYPE, null); " +
            "  var btn = it2.iterateNext(); " +
            "  var foundBtn = false; " +
            "  while(btn) { " +
            "    if (!btn.innerText.includes('선택')) { " +
            "       results.push({type: 'button', coords: getCoords(btn)}); " +
            "       foundBtn = true; " +
            "    } " +
            "    btn = it2.iterateNext(); " +
            "  } " +
            "  " +
            "  // 3. Fallback for Button if not found in DOM but likely there " +
            "  if (!foundBtn) { results.push({type: 'fallback_button', coords: {x: 45, y: 1900 - 78, w: 990, h: 144}}); } " +
            "  " +
            "  return JSON.stringify(results); " +
            "})();";

        wv.evaluateJavascript(jsPayload, Java.registerClass({
            name: "com.frida.WebCallbackV11_" + Math.floor(Math.random()*100000) + "_" + attempt,
            implements: [Java.use("android.webkit.ValueCallback")],
            methods: {
                onReceiveValue: function(value) {
                    if (!value || value === "null" || value === "[]") {
                        setTimeout(function() { executeAgreement(wv, attempt + 1); }, 1500);
                        return;
                    }
                    try {
                        var items = JSON.parse(value.replace(/^"|"$/g, '').replace(/\\"/g, '"'));
                        var MotionEvent = Java.use("android.view.MotionEvent");
                        var SystemClock = Java.use("android.os.SystemClock");

                        items.forEach(function(item, index) {
                            setTimeout(function() {
                                var relX = item.coords.x + (item.coords.w / 2);
                                var relY = item.coords.y + (item.coords.h / 2);
                                var absX = wvX + relX;
                                var absY = wvY + relY;

                                console.log("[Frida 🤖] 클릭 (" + item.type + "): (" + Math.round(absX) + ", " + Math.round(absY) + ")");
                                var now = SystemClock.uptimeMillis();
                                wv.dispatchTouchEvent(MotionEvent.obtain(now, now, 0, absX, absY, 0));
                                wv.dispatchTouchEvent(MotionEvent.obtain(now, now + 10, 1, absX, absY, 0));
                            }, index * 800);
                        });
                    } catch(e) {
                        console.log("[Frida 🤖] JS Parse Error: " + e);
                    }
                }
            }
        }).$new());
    }

    // --- 3. N-Log Interceptor (The Trigger) ---
    function hookOkHttp() {
        try {
            var OkHttpClient = Java.use("okhttp3.OkHttpClient");
            OkHttpClient.newCall.implementation = function(request) {
                var url = request.url().toString();
                if (url.includes("nlogapp") || url.includes("/n")) {
                    Java.scheduleOnMainThread(function() {
                        Java.choose("android.webkit.WebView", {
                            onMatch: function(wv) { executeAgreement(wv); },
                            onComplete: function() {}
                        });
                    });
                }
                return this.newCall(request);
            };
            console.log("[Frida 🤖] OkHttp 훅 설치 완료");
        } catch(e) {
            setTimeout(function() { Java.perform(hookOkHttp); }, 3000);
        }
    }

    hookOkHttp();
});
