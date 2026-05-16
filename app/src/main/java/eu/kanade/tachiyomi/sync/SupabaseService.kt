package eu.kanade.tachiyomi.sync

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest

/**
 * Singleton Supabase client for cloud sync.
 *
 * URL + anon key are baked in: they are intended for public client use
 * (RLS policies on the DB prevent users from reading each other's data).
 */
object SupabaseService {

    private const val SUPABASE_URL = "https://zaoapdkujobchvlnxikz.supabase.co"
    private const val SUPABASE_ANON_KEY = "sb_publishable_WuV0GGWSSzRF1FuP1VejJA_6fzS-2Xk"

    val client: SupabaseClient by lazy {
        createSupabaseClient(
            supabaseUrl = SUPABASE_URL,
            supabaseKey = SUPABASE_ANON_KEY,
        ) {
            install(Auth)
            install(Postgrest)
        }
    }

    val auth get() = client.auth
}
