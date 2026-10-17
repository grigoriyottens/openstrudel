package app.openstrudel

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    val model: HomeViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (savedInstanceState == null) intent?.dataString?.let(model::inspectLink)
        setContent {
            val colors =
                if (isSystemInDarkTheme())
                    darkColorScheme(
                        primary = Color(0xFFD3C0DF),
                        onPrimary = Color(0xFF342341),
                        background = Color(0xFF171717),
                        surface = Color(0xFF171717),
                        surfaceContainer = Color(0xFF242326),
                        secondaryContainer = Color(0xFF38303F),
                    )
                else
                    lightColorScheme(
                        primary = Color(0xFF6D4E82),
                        onPrimary = Color.White,
                        background = Color(0xFFFFFCF7),
                        surface = Color(0xFFFFFCF7),
                        surfaceContainer = Color(0xFFF2EDE7),
                        secondaryContainer = Color(0xFFEFE1F5),
                    )
            MaterialTheme(colorScheme = colors) { OpenStrudelApp(model) }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.dataString?.let(model::inspectLink)
    }

    override fun onStop() {
        lifecycleScope.launch { model.flushDrafts() }
        super.onStop()
    }
}
