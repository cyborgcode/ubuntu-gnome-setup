import Atk from 'gi://Atk';
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {QuickMenuToggle, SystemIndicator} from 'resource:///org/gnome/shell/ui/quickSettings.js';

// The AppIndicator extension puts every tray icon in the top bar under the role "appindicator-<id>".
const ROLE_PREFIX = 'appindicator-';
// Built-in top-bar indicators the toggle hides too, by their panel role.
const SHELL_INDICATORS = new Map([
    ['a11y', {name: 'Accessibility', icon: 'accessibility-menu-symbolic'}],
]);
// Apps whose tray icon is drawn with an icon shipped in this extension's folder instead of their own. An app is
// matched by its tray icon's id/title, or by the command line of the process that owns the icon.
const CUSTOM_ICONS = [
    {pattern: /filee/i, file: 'filee-tray.svg'},
    {pattern: /beeper/i, file: 'beeper-tray.svg'},
];
const TOGGLE_ICON = 'view-reveal-symbolic';
const FALLBACK_APP_ICON = 'application-x-executable-symbolic';
const LOG_TAG = '[filee-tray-toggle]';

const TrayToggle = GObject.registerClass(
class TrayToggle extends QuickMenuToggle {
    constructor() {
        super({
            title: 'Tray icons',
            iconName: TOGGLE_ICON,
            toggleMode: true,
        });
        this.menu.setHeader(TOGGLE_ICON, 'Tray icons', 'Checked icons stay visible when hidden');
        this.list = new PopupMenu.PopupMenuSection();
        this.menu.addMenuItem(this.list);
    }
});

// One tray icon in the toggle's menu. Clicking it flips its exception without closing the menu,
// so several can be picked in one go.
const ExceptionItem = GObject.registerClass(
class ExceptionItem extends PopupMenu.PopupImageMenuItem {
    constructor(text, icon, kept, onToggle) {
        super(text, icon);
        this.accessible_role = Atk.Role.CHECK_MENU_ITEM;
        this._onToggle = onToggle;
        this._showKept(kept);
    }

    activate(_event) {
        this._showKept(this._onToggle());
    }

    _showKept(kept) {
        this.setOrnament(kept ? PopupMenu.Ornament.CHECK : PopupMenu.Ornament.NONE);
    }
});

const TrayIndicator = GObject.registerClass(
class TrayIndicator extends SystemIndicator {
    constructor(toggle) {
        super();
        this.quickSettingsItems.push(toggle);
    }
});

export default class TrayIconsToggleExtension extends Extension {
    enable() {
        this._cancellable = new Gio.Cancellable();
        this._tracked = new Map(); // role -> entry, for every tray icon and SHELL_INDICATORS entry in the top bar
        this._scanSource = 0;
        ({shown: this._shown, exceptions: this._exceptions} = this._loadState());

        this._toggle = new TrayToggle();
        this._toggle.checked = this._shown;
        this._updateSubtitle();
        this._toggle.connect('notify::checked', () => this._onToggled());
        this._toggle.menu.connect('open-state-changed', (_menu, open) => {
            if (open)
                this._syncMenu();
        });
        this._indicator = new TrayIndicator(this._toggle);
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);

        // New tray icons arrive as children of one of the panel boxes.
        this._boxes = [Main.panel._leftBox, Main.panel._centerBox, Main.panel._rightBox]
            .filter(box => box);
        this._boxIds = this._boxes.map(box => box.connect('child-added', () => this._scheduleScan()));
        this._scan();
    }

    disable() {
        this._cancellable?.cancel();
        this._cancellable = null;

        if (this._scanSource) {
            GLib.Source.remove(this._scanSource);
            this._scanSource = 0;
        }
        this._boxes?.forEach((box, i) => {
            try { box.disconnect(this._boxIds[i]); } catch (_e) { /* box already gone */ }
        });
        this._boxes = null;
        this._boxIds = null;

        // Give every icon back as it was, so disabling the extension (or locking the screen) never leaves one hidden.
        this._tracked?.forEach(entry => this._release(entry));
        this._tracked = null;

        this._indicator?.quickSettingsItems.forEach(item => item.destroy());
        this._indicator?.destroy();
        this._indicator = null;
        this._toggle = null;
    }

    // ---- icon discovery -------------------------------------------------------------------------------------

    _scheduleScan() {
        if (this._scanSource)
            return;
        this._scanSource = GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            this._scanSource = 0;
            this._scan();
            return GLib.SOURCE_REMOVE;
        });
    }

    _scan() {
        if (!this._tracked)
            return;
        for (const [role, icon] of Object.entries(Main.panel.statusArea)) {
            if ((role.startsWith(ROLE_PREFIX) || SHELL_INDICATORS.has(role)) && icon && !this._tracked.has(role))
                this._track(role, icon);
        }
    }

    _track(role, icon) {
        // The wrapper the panel puts every icon in. Hiding it removes the icon's slot too, and leaves the icon
        // itself to the AppIndicator extension, which shows and hides it as the app's status changes.
        const {container} = icon;
        if (!container)
            return;
        const entry = {
            role,
            icon,
            container,
            indicator: icon._indicator ?? null, // set for app indicators, absent for legacy tray icons
            containerVisibleId: 0,
            destroyId: 0,
            readyId: 0,
            custom: null,                       // CUSTOM_ICONS apps only: the icon we draw instead of the app's own
            childAddedId: 0,
            suppressed: new Map(),              // CUSTOM_ICONS apps only: the app's own icon parts we keep hidden
        };
        // The panel shows the wrapper again whenever it re-adds the icon (for example when the tray position
        // setting changes), so hide it once more if it should stay hidden.
        entry.containerVisibleId = container.connect('notify::visible', () => {
            if (container.visible && !this._isShown(entry))
                container.visible = false;
        });
        entry.destroyId = icon.connect('destroy', () => {
            if (this._tracked?.get(role) === entry)
                this._tracked.delete(role);
            this._refreshMenu();
        });
        // An app's id, which exceptions are keyed by, is only known once its indicator is ready.
        if (entry.indicator) {
            entry.readyId = entry.indicator.connect('ready', () => {
                this._apply(entry);
                this._refreshMenu();
            });
        }
        this._tracked.set(role, entry);
        this._findCustomIcon(entry);
        this._apply(entry);
        this._refreshMenu();
    }

    // Exceptions are keyed by the id the app gives its tray icon (the same id the AppIndicator extension's own
    // settings use), by window class for legacy tray icons, or by panel role for built-in indicators.
    _keyOf({role, icon, indicator}) {
        if (SHELL_INDICATORS.has(role))
            return `shell:${role}`;
        if (indicator)
            return indicator.id || null;
        const wmClass = icon.icon?.wm_class;
        return wmClass ? `legacy:${wmClass}` : null;
    }

    _nameOf({role, icon, indicator}) {
        if (SHELL_INDICATORS.has(role))
            return SHELL_INDICATORS.get(role).name;
        if (indicator)
            return indicator._appInfo?.get_display_name() || indicator.title || indicator.id;
        return icon.icon?.title || icon.icon?.wm_class;
    }

    // A Gio.Icon or icon name for the entry's row in the menu.
    _iconOf({role, icon}) {
        return SHELL_INDICATORS.get(role)?.icon ?? icon.icon?.gicon ?? null;
    }

    // ---- showing and hiding icons ---------------------------------------------------------------------------

    _isShown(entry) {
        return this._shown || this._exceptions.has(this._keyOf(entry));
    }

    _applyAll() {
        this._tracked?.forEach(entry => this._apply(entry));
    }

    _apply(entry) {
        entry.container.visible = this._isShown(entry);
    }

    _release(entry) {
        const {icon, container} = entry;
        const attempt = fn => {
            try { fn(); } catch (_e) { /* the actor is already destroyed */ }
        };
        attempt(() => container.disconnect(entry.containerVisibleId));
        attempt(() => icon.disconnect(entry.destroyId));
        if (entry.readyId)
            attempt(() => entry.indicator.disconnect(entry.readyId));
        if (entry.childAddedId)
            attempt(() => icon.disconnect(entry.childAddedId));
        entry.suppressed.forEach((record, child) => attempt(() => {
            child.disconnect(record.id);
            child.visible = record.wasVisible;
        }));
        entry.suppressed.clear();
        if (entry.custom) {
            attempt(() => icon.remove_child(entry.custom));
            attempt(() => entry.custom.destroy());
            entry.custom = null;
        }
        attempt(() => { container.visible = true; }); // how the panel leaves every wrapper it places
    }

    // ---- replacing app icons with CUSTOM_ICONS ---------------------------------------------------------------

    _findCustomIcon(entry) {
        const {indicator} = entry;
        if (!indicator)
            return;
        const custom = this._customIconFor(`${indicator.id ?? ''} ${indicator.title ?? ''}`);
        if (custom)
            this._replaceContent(entry, custom.file);
        else
            this._checkProcess(entry, indicator.busName);
    }

    _customIconFor(text) {
        return CUSTOM_ICONS.find(({pattern}) => pattern.test(text));
    }

    // The id/title can be empty or generic, so also ask the bus which process owns the icon.
    _checkProcess(entry, busName) {
        if (!busName)
            return;
        Gio.DBus.session.call(
            'org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus',
            'GetConnectionUnixProcessID', new GLib.Variant('(s)', [busName]), new GLib.VariantType('(u)'),
            Gio.DBusCallFlags.NONE, -1, this._cancellable,
            (connection, result) => {
                let pid;
                try {
                    [pid] = connection.call_finish(result).deepUnpack();
                } catch (_e) {
                    return; // cancelled, or the icon's owner left the bus
                }
                if (this._tracked?.get(entry.role) !== entry)
                    return;
                const custom = this._customIconFor(this._readCmdline(pid));
                if (custom)
                    this._replaceContent(entry, custom.file);
            });
    }

    _readCmdline(pid) {
        try {
            const [ok, bytes] = GLib.file_get_contents(`/proc/${pid}/cmdline`);
            return ok ? new TextDecoder().decode(bytes).replaceAll('\0', ' ') : '';
        } catch (_e) {
            return '';
        }
    }

    // Puts our own icon in the tray button and keeps everything the app drew there hidden, so nothing shows through.
    _replaceContent(entry, iconFile) {
        if (entry.custom)
            return;
        const file = Gio.File.new_for_path(GLib.build_filenamev([this.path, iconFile]));
        if (!file.query_exists(null)) {
            console.log(`${LOG_TAG} ${iconFile} is missing from the extension folder, keeping the app's own icon`);
            return;
        }
        console.log(`${LOG_TAG} drawing ${iconFile} for ${entry.role}`);
        const {icon} = entry;
        const custom = new St.Icon({
            gicon: new Gio.FileIcon({file}),
            style_class: 'system-status-icon',
            y_align: Clutter.ActorAlign.CENTER,
        });
        entry.custom = custom;
        // A panel button sizes itself from its first child, so ours goes first.
        icon.insert_child_at_index(custom, 0);
        for (const child of icon.get_children()) {
            if (child !== custom)
                this._suppress(entry, child);
        }
        // Anything the AppIndicator extension adds later (a rebuilt icon, an overlay) is hidden too.
        entry.childAddedId = icon.connect('child-added', (_actor, child) => {
            if (child !== custom && !entry.suppressed.has(child))
                this._suppress(entry, child);
        });
    }

    _suppress(entry, child) {
        const record = {wasVisible: child.visible, enforcing: false, id: 0};
        record.id = child.connect('notify::visible', () => {
            if (record.enforcing)
                return;
            record.wasVisible = child.visible;
            if (child.visible) {
                record.enforcing = true;
                child.visible = false;
                record.enforcing = false;
            }
        });
        entry.suppressed.set(child, record);
        record.enforcing = true;
        child.visible = false;
        record.enforcing = false;
    }

    // ---- toggle, exceptions menu and saved state ------------------------------------------------------------

    _onToggled() {
        this._shown = this._toggle.checked;
        this._updateSubtitle();
        this._saveState();
        this._applyAll();
    }

    // Returns whether the icon is now an exception.
    _toggleException(key, name) {
        if (this._exceptions.has(key))
            this._exceptions.delete(key);
        else
            this._exceptions.set(key, name);
        this._updateSubtitle();
        this._saveState();
        this._applyAll();
        return this._exceptions.has(key);
    }

    _updateSubtitle() {
        if (this._shown)
            this._toggle.subtitle = 'Shown';
        else if (this._exceptions.size)
            this._toggle.subtitle = `Hidden except ${this._exceptions.size}`;
        else
            this._toggle.subtitle = 'Hidden';
    }

    _refreshMenu() {
        if (this._toggle?.menu.isOpen)
            this._syncMenu();
    }

    // Lists the icons the top bar would show now. Exceptions for apps that aren't running stay saved but aren't
    // listed, and apply again when the app comes back.
    _syncMenu() {
        const {list} = this._toggle;
        list.removeAll();

        const rows = new Map(); // key -> {name, icon}
        for (const entry of this._tracked.values()) {
            const key = this._keyOf(entry);
            if (!key || rows.has(key) || !(entry.icon.visible || this._exceptions.has(key)))
                continue;
            rows.set(key, {name: this._nameOf(entry), icon: this._iconOf(entry)});
        }
        const present = [...rows].sort(([, a], [, b]) => a.name.localeCompare(b.name));
        for (const [key, {name, icon}] of present) {
            list.addMenuItem(new ExceptionItem(name, icon ?? FALLBACK_APP_ICON,
                this._exceptions.has(key), () => this._toggleException(key, name)));
        }

        if (list.isEmpty())
            list.addMenuItem(new PopupMenu.PopupMenuItem('No tray icons right now', {reactive: false}));
    }

    _stateFile() {
        return GLib.build_filenamev([GLib.get_user_config_dir(), 'filee-tray-toggle', 'state.json']);
    }

    // Shown unless the user last chose to hide them, and no exceptions until the user picks some.
    _loadState() {
        try {
            const [, bytes] = GLib.file_get_contents(this._stateFile());
            const saved = JSON.parse(new TextDecoder().decode(bytes));
            return {
                shown: saved.shown !== false,
                exceptions: new Map(Object.entries(saved.exceptions ?? {})), // key -> app name
            };
        } catch (_e) {
            return {shown: true, exceptions: new Map()}; // first run, or an unreadable file
        }
    }

    _saveState() {
        try {
            const file = this._stateFile();
            GLib.mkdir_with_parents(GLib.path_get_dirname(file), 0o700);
            const state = {shown: this._shown, exceptions: Object.fromEntries(this._exceptions)};
            GLib.file_set_contents(file, new TextEncoder().encode(JSON.stringify(state)));
        } catch (e) {
            console.error(`${LOG_TAG} could not save state: ${e.message}`);
        }
    }
}
