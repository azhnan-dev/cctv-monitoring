/**
 * Pemuat config bersama.
 *
 * Path default tetap ./config.json di root aplikasi. Di container, path
 * diarahkan ke volume lewat CCTV_CONFIG_PATH supaya pengaturan yang diubah
 * dari panel admin tidak hilang saat container di-redeploy.
 */
const fs = require('fs');
const path = require('path');

const DEFAULT_FILE = path.join(__dirname, '..', 'config.json');
const FALLBACK_FILE = path.join(__dirname, '..', 'config.default.json');

const CONFIG_FILE = process.env.CCTV_CONFIG_PATH
    ? path.resolve(process.env.CCTV_CONFIG_PATH)
    : DEFAULT_FILE;

function readConfigFile(file) {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function loadConfig() {
    try {
        return readConfigFile(CONFIG_FILE);
    } catch (err) {
        if (CONFIG_FILE !== DEFAULT_FILE && fs.existsSync(FALLBACK_FILE)) {
            console.warn(`[Config] ${CONFIG_FILE} belum ada (${err.code || err.message}); memakai config.default.json`);
            return readConfigFile(FALLBACK_FILE);
        }
        throw err;
    }
}

const config = loadConfig();

// Override host MediaMTX dari environment (dipakai docker compose: "mediamtx")
if (process.env.MEDIAMTX_HOST) {
    config.mediamtx = config.mediamtx || {};
    config.mediamtx.host = process.env.MEDIAMTX_HOST;
}

module.exports = { CONFIG_FILE, config };
