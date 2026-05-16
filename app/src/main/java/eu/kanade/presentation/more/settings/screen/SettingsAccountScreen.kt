package eu.kanade.presentation.more.settings.screen

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import cafe.adriel.voyager.navigator.LocalNavigator
import cafe.adriel.voyager.navigator.currentOrThrow
import eu.kanade.presentation.components.AppBar
import eu.kanade.presentation.util.Screen
import eu.kanade.tachiyomi.sync.SupabaseService
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.exceptions.RestException
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import tachiyomi.presentation.core.components.material.Scaffold

object SettingsAccountScreen : Screen() {

    /** Map raw exceptions to user-friendly messages. */
    private fun friendlyError(e: Throwable): String {
        val msg = e.message.orEmpty().lowercase()
        return when {
            e is RestException && msg.contains("invalid login credentials") ->
                "Wrong email or password."
            e is RestException && msg.contains("user already registered") ->
                "An account with this email already exists. Try signing in."
            e is RestException && msg.contains("email rate limit exceeded") ->
                "Too many requests. Please wait a minute and try again."
            e is RestException && msg.contains("password should be at least") ->
                "Password is too short. Use at least 6 characters."
            e is RestException && msg.contains("invalid email") ->
                "That doesn't look like a valid email address."
            msg.contains("unable to resolve host") || msg.contains("failed to connect") ||
                msg.contains("timeout") || msg.contains("network") ->
                "No internet connection. Check your network and try again."
            else -> "Something went wrong. Please try again."
        }
    }

    @Composable
    override fun Content() {
        val navigator = LocalNavigator.currentOrThrow
        val scope = rememberCoroutineScope()
        val auth = SupabaseService.auth

        var email by remember { mutableStateOf("") }
        var password by remember { mutableStateOf("") }
        var status by remember { mutableStateOf("Not signed in") }
        var loggedInEmail by remember { mutableStateOf<String?>(null) }

        LaunchedEffect(Unit) {
            auth.sessionStatus.collectLatest { s ->
                when (s) {
                    is SessionStatus.Authenticated -> {
                        loggedInEmail = s.session.user?.email
                        status = "Signed in as ${loggedInEmail ?: "(unknown)"}"
                    }
                    is SessionStatus.NotAuthenticated -> {
                        loggedInEmail = null
                        status = "Not signed in"
                    }
                    is SessionStatus.Initializing -> status = "Loading…"
                    is SessionStatus.RefreshFailure -> status = "Session expired. Please sign in again."
                }
            }
        }

        Scaffold(
            topBar = { scrollBehavior ->
                AppBar(
                    title = "Account",
                    navigateUp = navigator::pop,
                    scrollBehavior = scrollBehavior,
                )
            },
            content = { contentPadding ->
                Content(
                    contentPadding = contentPadding,
                    status = status,
                    signedIn = loggedInEmail != null,
                    email = email,
                    onEmailChange = { email = it },
                    password = password,
                    onPasswordChange = { password = it },
                    onLogin = {
                        scope.launch {
                            status = "Signing in…"
                            try {
                                auth.signInWith(Email) {
                                    this.email = email
                                    this.password = password
                                }
                            } catch (e: Exception) {
                                status = friendlyError(e)
                            }
                        }
                    },
                    onRegister = {
                        scope.launch {
                            status = "Creating account…"
                            try {
                                auth.signUpWith(Email) {
                                    this.email = email
                                    this.password = password
                                }
                                status = "Account created. Signing you in…"
                            } catch (e: Exception) {
                                status = friendlyError(e)
                            }
                        }
                    },
                    onResetPassword = {
                        scope.launch {
                            if (email.isBlank()) {
                                status = "Enter your email above, then tap Reset password."
                                return@launch
                            }
                            status = "Sending reset email…"
                            try {
                                auth.resetPasswordForEmail(email)
                                status = "Reset email sent to $email. Check your inbox."
                            } catch (e: Exception) {
                                status = friendlyError(e)
                            }
                        }
                    },
                    onSignOut = {
                        scope.launch {
                            try {
                                auth.signOut()
                            } catch (e: Exception) {
                                status = friendlyError(e)
                            }
                        }
                    },
                )
            },
        )
    }

    @Composable
    private fun Content(
        contentPadding: PaddingValues,
        status: String,
        signedIn: Boolean,
        email: String,
        onEmailChange: (String) -> Unit,
        password: String,
        onPasswordChange: (String) -> Unit,
        onLogin: () -> Unit,
        onRegister: () -> Unit,
        onResetPassword: () -> Unit,
        onSignOut: () -> Unit,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(contentPadding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(text = status)
            HorizontalDivider()

            if (!signedIn) {
                OutlinedTextField(
                    value = email,
                    onValueChange = onEmailChange,
                    label = { Text("Email") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    singleLine = true,
                    modifier = Modifier.fillMaxSize(),
                )
                OutlinedTextField(
                    value = password,
                    onValueChange = onPasswordChange,
                    label = { Text("Password") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    modifier = Modifier.fillMaxSize(),
                )
                Button(onClick = onLogin, modifier = Modifier.fillMaxSize()) { Text("Sign in") }
                OutlinedButton(onClick = onRegister, modifier = Modifier.fillMaxSize()) {
                    Text("Create account")
                }
                TextButton(onClick = onResetPassword, modifier = Modifier.fillMaxSize()) {
                    Text("Forgot password?")
                }
            } else {
                Button(onClick = onSignOut, modifier = Modifier.fillMaxSize()) { Text("Sign out") }
            }
        }
    }
}
