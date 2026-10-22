/* ============================================================================
 * NovaLife Hub Firmware - Local Configuration Template
 * ============================================================================
 * INSTRUCTIONS:
 * 1. Copy or rename this file to "config_local.h" in the same directory:
 *      cp config_local.example.h config_local.h
 * 2. Edit "config_local.h" and populate your Wi-Fi credentials, Supabase
 *    credentials, and device secrets below.
 * 3. IMPORTANT: "config_local.h" contains sensitive secrets and is gitignored.
 *    NEVER commit "config_local.h" to version control.
 * ============================================================================
 */

#ifndef CONFIG_LOCAL_H
#define CONFIG_LOCAL_H

/* Wi-Fi Station Credentials */
#define WIFI_SSID ""
#define WIFI_PASS ""

/* 128-bit key for tag authentication and marking (interim key held on PS, loaded into PL)
 * Replace with your 16-byte hex key:
 */
static const unsigned char HUB_AES_ASCON_KEY[16] = {
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

/* Hub Device Identification & Secret for Supabase Cloud Queue Relay */
#define HUB_DEVICE_ID "board-1"
#define HUB_DEVICE_SECRET "YOUR_HUB_DEVICE_SECRET_HEX"

/* Supabase Cloud Connection Details */
#define SUPABASE_HOST "your-project-id.supabase.co"
#define SUPABASE_ANON_KEY "YOUR_SUPABASE_ANON_KEY"

#endif /* CONFIG_LOCAL_H */
