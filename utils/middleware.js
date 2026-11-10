// Authentication and middleware utilities
const session = require('express-session');
const fs = require('fs');
const path = require('path');
const DEBUG_AUTH = process.env.DEBUG_AUTH === '1';

const PROJECT_ROOT = path.join(__dirname, '..');

/**
 * Session store factory.
 *
 * Default: SQLite (persist across restart / auto-update) in a dedicated
 * sessions.db next to the app. Falls back to MemoryStore when the SQLite
 * store cannot be created, so a broken session table never blocks startup.
 *
 * Override via config.json -> server.session:
 *   { "store": "memory" }            -> force MemoryStore
 *   { "sqlite_db": "cameras.db" }    -> reuse the app DB instead
 *   { "sqlite_table": "sessions" }   -> table name (default)
 *
 * Default file is a dedicated sessions.db: cameras.db is tracked by git, so
 * writing sessions into it would dirty the repository on every login.
 */
function createSessionStore(config) {
    const sessionConfig = (config && config.server && config.server.session) || {};

    if (sessionConfig.store === 'memory') {
        console.log('[Session] Store: MemoryStore (dipaksa lewat config server.session.store)');
        return new session.MemoryStore();
    }

    const table = sessionConfig.sqlite_table || 'sessions';
    const dbFile = sessionConfig.sqlite_db || 'sessions.db';
    const dbPath = path.isAbsolute(dbFile) ? dbFile : path.join(PROJECT_ROOT, dbFile);

    try {
        // Fail fast (and fall back) when the DB file is unusable.
        if (fs.existsSync(dbPath)) {
            fs.accessSync(dbPath, fs.constants.R_OK | fs.constants.W_OK);
        } else {
            // Will be created on first write — check we may write into its folder.
            fs.accessSync(path.dirname(dbPath), fs.constants.W_OK);
        }

        const SQLiteStore = require('connect-sqlite3')(session);
        const store = new SQLiteStore({
            table,
            // connect-sqlite3 joins `dir` and `db` itself, so pass them split.
            db: path.basename(dbPath),
            dir: path.dirname(dbPath),
            concurrentDb: true // PRAGMA journal_mode = wal
        });

        console.log(`[Session] Store: SQLite (${dbPath}, tabel ${table})`);
        return store;
    } catch (err) {
        console.error(`[Session] SQLite store gagal dipakai (${err.message}). Fallback ke MemoryStore — sesi akan hilang saat restart.`);
        return new session.MemoryStore();
    }
}

function setupSessionMiddleware(app, config) {
    const behindProxy = config.server.behind_https_proxy === true;
    console.log(`[Config] behind_https_proxy: ${behindProxy}`);

    const sessionStore = createSessionStore(config);
    const sessionMiddleware = session({
        secret: config.server.session_secret || 'cctv-monitoring-secret-key',
        resave: false,
        saveUninitialized: false,
        store: sessionStore,
        proxy: behindProxy,
        cookie: {
            secure: behindProxy ? 'auto' : false,
            maxAge: 24 * 60 * 60 * 1000,
            sameSite: 'lax'
        }
    });

    app.use((req, res, next) => {
        sessionMiddleware(req, res, next);
    });

    // Debug middleware for session issues
    app.use((req, res, next) => {
        if (DEBUG_AUTH && req.path === '/login' && req.method === 'POST') {
            console.log(`[Debug] Login attempt - Host: ${req.headers.host}, Protocol: ${req.protocol}, Secure: ${req.secure}`);
            console.log(`[Debug] Headers:`, {
                'x-forwarded-proto': req.headers['x-forwarded-proto'],
                'x-forwarded-for': req.headers['x-forwarded-for']
            });
        }
        next();
    });
}

function setupGlobalMiddleware(app, config, getHlsBaseUrl) {
    app.use((req, res, next) => {
        res.locals.base_path = app.locals.base_path || '';
        res.locals.site = config.site || {};
        res.locals.hlsBaseUrl = getHlsBaseUrl(req, config);
        res.locals.months = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
        res.locals.isAdmin = !!req.session.user;
        res.locals.isCustomer = !!req.session.customer;
        res.locals.session = req.session;
        res.locals.user = req.session.customer || req.session.user || {};
        res.locals.userStatus = JSON.stringify({
            isAdmin: res.locals.isAdmin,
            isCustomer: res.locals.isCustomer,
            customerId: req.session.customer ? req.session.customer.id : null,
            customerLevel: req.session.customer ? req.session.customer.level : (req.session.user ? 'admin' : 'umum')
        });
        next();
    });
}

function requireAuth(ADMIN_USER) {
    return (req, res, next) => {
        if (req.session && req.session.user === ADMIN_USER) {
            return next();
        }
        if (DEBUG_AUTH) {
            console.log(`[Auth] Redirecting to login - No valid session (${req.path})`);
        }
        const basePath = req.app.locals.base_path || '';
        res.redirect(basePath + '/login');
    };
}

function requireApiAuth(ADMIN_USER) {
    return (req, res, next) => {
        if (req.session && req.session.user === ADMIN_USER) {
            return next();
        }
        if (DEBUG_AUTH) {
            console.error(`[API Auth] Unauthorized access attempt (${req.path})`);
        }
        res.status(401).json({ error: 'Unauthorized', message: 'Anda harus login sebagai admin' });
    };
}

function requireAnyAuth(req, res, next) {
    if (req.session && (req.session.user || req.session.customer)) {
        return next();
    }
    const basePath = req.app.locals.base_path || '';
    res.redirect(basePath + '/user/login');
}

module.exports = {
    createSessionStore,
    setupSessionMiddleware,
    setupGlobalMiddleware,
    requireAuth,
    requireApiAuth,
    requireAnyAuth
};

// Made with Bob
