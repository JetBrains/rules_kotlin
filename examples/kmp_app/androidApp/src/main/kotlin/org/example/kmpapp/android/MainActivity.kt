package org.example.kmpapp.android

import android.app.Activity
import android.os.Bundle
import android.widget.TextView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.example.kmpapp.Greeting

/**
 * Shows the greeting of the shared code, then the one it gives a moment later. The coroutine runs on
 * Dispatchers.Default and posts its result to the UI thread, so the app needs no
 * kotlinx-coroutines-android.
 */
class MainActivity : Activity() {
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val text = TextView(this)
    text.text = Greeting().greet()
    setContentView(text)
    scope.launch {
      val greeting = Greeting().greetLater()
      runOnUiThread { text.text = greeting }
    }
  }

  override fun onDestroy() {
    scope.cancel()
    super.onDestroy()
  }
}
