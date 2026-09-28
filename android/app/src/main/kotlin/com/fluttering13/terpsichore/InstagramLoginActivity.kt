package com.fluttering13.terpsichore

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** Password and verification inputs stay in Instagram's HTTPS page. */
class InstagramLoginActivity : Activity() {
    private var browser: WebView? = null
    private lateinit var status: TextView
    private val en get() = intent.getBooleanExtra("english", false)
    private fun label(zh: String, english: String) = if (en) english else zh

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(20, 20, 20, 20) }
        setContentView(layout)
        layout.setOnApplyWindowInsetsListener { view, insets ->
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                val bars = insets.getInsets(android.view.WindowInsets.Type.systemBars() or android.view.WindowInsets.Type.displayCutout())
                view.setPadding(bars.left + 20, bars.top + 20, bars.right + 20, bars.bottom + 20)
            } else {
                @Suppress("DEPRECATION")
                view.setPadding(insets.systemWindowInsetLeft + 20, insets.systemWindowInsetTop + 20,
                    insets.systemWindowInsetRight + 20, insets.systemWindowInsetBottom + 20)
            }
            insets
        }
        status = TextView(this).apply {
            text = label("在 Instagram 網頁登入並完成驗證，再按「登入完成」。登入狀態只儲存在此手機。",
                "Sign in on Instagram and complete verification, then tap Done. Your session stays on this device.")
        }
        layout.addView(status)
        layout.addView(Button(this).apply {
            text = label("取消", "Cancel")
            setOnClickListener { setResult(RESULT_CANCELED); finish() }
        })
        if (intent.getStringExtra("mode") == "import") {
            status.text = label("選擇瀏覽器匯出的 Netscape 格式 cookies.txt；只匯入 Instagram 登入資料。",
                "Choose a Netscape cookies.txt file exported from your browser. Only Instagram cookies are imported.")
            layout.addView(Button(this).apply {
                text = label("選擇登入資料檔案", "Choose cookies file")
                setOnClickListener { pickFile() }
            })
            if (state == null) pickFile()
            return
        }
        layout.addView(Button(this).apply {
            text = label("登入完成", "Done")
            setOnClickListener {
                try {
                    val header = CookieManager.getInstance().getCookie("https://www.instagram.com/").orEmpty()
                    InstagramSessionStore(this@InstagramLoginActivity).save(InstagramCookies.fromWebView(header))
                    setResult(RESULT_OK); finish()
                } catch (_: Exception) {
                    status.text = label("尚未取得登入狀態，請先登入並完成驗證；也可返回改用匯入登入狀態。",
                        "No session found. Finish signing in and verification, or go back and import cookies.")
                }
            }
        })
        browser = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
            CookieManager.getInstance().setAcceptCookie(true)
            CookieManager.getInstance().setAcceptThirdPartyCookies(this, false)
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val host = request.url.host.orEmpty().lowercase()
                    return request.url.scheme != "https" ||
                        (host != "instagram.com" && !host.endsWith(".instagram.com"))
                }
            }
            loadUrl("https://www.instagram.com/accounts/login/")
        }
        layout.addView(browser, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
    }

    private fun pickFile() {
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE); type = "*/*"
        }, 701)
    }

    @Deprecated("Activity result bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 701 || resultCode != RESULT_OK) return
        try {
            val uri: Uri = data?.data ?: return
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (output.size() + count > 1024 * 1024) throw DownloadFailure("IG_INVALID_COOKIES")
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            } ?: throw DownloadFailure("IG_INVALID_COOKIES")
            InstagramSessionStore(this).save(String(bytes, Charsets.UTF_8))
            setResult(RESULT_OK); finish()
        } catch (_: Exception) {
            status.text = label("無法匯入：請選擇有效且未過期、包含 Instagram 登入狀態的 Netscape cookies.txt。",
                "Import failed. Choose a valid Netscape cookies.txt with an unexpired Instagram session.")
        }
    }

    override fun onDestroy() {
        browser?.apply {
            stopLoading()
            clearCache(true)
            destroy()
            android.webkit.WebStorage.getInstance().deleteAllData()
            CookieManager.getInstance().removeAllCookies { CookieManager.getInstance().flush() }
        }
        super.onDestroy()
    }
}
