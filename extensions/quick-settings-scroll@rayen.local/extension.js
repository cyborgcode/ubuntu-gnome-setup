import Clutter from 'gi://Clutter';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {PopupMenuBase} from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

// Space kept free between the bottom of Quick Settings and the bottom of the screen
const SCREEN_MARGIN = 12;
// How long the panel glides after a wheel click, in milliseconds
const SCROLL_DURATION = 200;

// Quick Settings grows downward without limit, so a tall toggle menu runs off the bottom of the screen.
// Scrolling over the panel slides the whole panel up (behind the top bar) until its bottom is in view.
// Sliders keep the wheel for their own value, because they stop the scroll event before it gets here.
export default class QuickSettingsScrollExtension extends Extension {
    enable() {
        const qsMenu = this._qsMenu = Main.panel.statusArea.quickSettings.menu;
        this._offset = 0;

        // The panel and its toggle menus are both children of qsMenu.actor, so moving it moves them together.
        // Each open toggle menu holds its own input grab, so scrolls stop at that menu instead of reaching
        // qsMenu.actor: listen on the menus as well.
        this._watchScroll(qsMenu.actor);
        for (const actor of qsMenu._overlay)
            this._watchScroll(actor);
        qsMenu._overlay.connectObject('child-added', (_, actor) => this._watchScroll(actor), this);

        // A menu closing shrinks the panel; slide back down so its bottom stays on the screen edge
        qsMenu._boxPointer.connectObject('notify::height', () => {
            if (this._offset > this._maxOffset())
                this._setOffset(this._offset);
        }, this);
        qsMenu.connectObject('open-state-changed', (_, isOpen) => {
            if (!isOpen)
                return;
            // Under the top bar, the part slid past the top goes behind the bar. The shell restacks
            // the panel above the bar again after startup, so this is redone on every open.
            const {uiGroup, panelBox} = Main.layoutManager;
            if (qsMenu.actor.get_parent() === uiGroup)
                uiGroup.set_child_below_sibling(qsMenu.actor, panelBox);
            this._setOffset(0);
        }, this);
        global.stage.connectObject('notify::key-focus', () => this._revealFocus(), this);
    }

    disable() {
        const qsMenu = this._qsMenu;
        qsMenu.actor.disconnectObject(this);
        for (const actor of qsMenu._overlay)
            actor.disconnectObject(this);
        qsMenu._overlay.disconnectObject(this);
        qsMenu._boxPointer.disconnectObject(this);
        qsMenu.disconnectObject(this);
        global.stage.disconnectObject(this);

        qsMenu.actor.remove_transition('translation-y');
        qsMenu.actor.translation_y = 0;
        const {uiGroup, panelBox} = Main.layoutManager;
        if (qsMenu.actor.get_parent() === uiGroup)
            uiGroup.set_child_above_sibling(qsMenu.actor, panelBox);

        this._qsMenu = null;
    }

    _watchScroll(actor) {
        actor.connectObject('scroll-event', (_, event) => this._onScroll(event), this);
    }

    _workArea() {
        const boxPointer = this._qsMenu._boxPointer;
        const monitor = Main.layoutManager.findMonitorForActor(boxPointer) ?? Main.layoutManager.primaryMonitor;
        return Main.layoutManager.getWorkAreaForMonitor(monitor.index);
    }

    // How far the panel has to slide up for its bottom to sit SCREEN_MARGIN above the bottom of the screen
    // Measured from positions rather than the on-screen transform, which leaves out the slide and isn't
    // known until the panel is first laid out
    _maxOffset() {
        const boxPointer = this._qsMenu._boxPointer;
        const workArea = this._workArea();
        const bottom = this._qsMenu.actor.y + boxPointer.y + boxPointer.height;
        return Math.max(0, bottom - (workArea.y + workArea.height - SCREEN_MARGIN));
    }

    // _offset is where the panel is headed; with animate it glides there, picking up from wherever
    // an earlier glide has got to, so quick wheel clicks add up into one smooth movement
    _setOffset(offset, animate = false) {
        // A focused actor that isn't laid out yet has no position
        if (!Number.isFinite(offset))
            return;
        this._offset = Math.clamp(offset, 0, this._maxOffset());

        const {actor} = this._qsMenu;
        if (animate) {
            actor.ease({
                translation_y: -this._offset,
                duration: SCROLL_DURATION,
                mode: Clutter.AnimationMode.EASE_OUT_CUBIC,
            });
        } else {
            actor.remove_transition('translation-y');
            actor.translation_y = -this._offset;
        }
    }

    _onScroll(event) {
        // Each wheel click also arrives as a copy in the other scroll format, like in St.ScrollView
        if (event.is_pointer_emulated())
            return this._maxOffset() === 0 ? Clutter.EVENT_PROPAGATE : Clutter.EVENT_STOP;

        let dy;
        switch (event.get_scroll_direction()) {
        case Clutter.ScrollDirection.UP:
            dy = -1;
            break;
        case Clutter.ScrollDirection.DOWN:
            dy = 1;
            break;
        case Clutter.ScrollDirection.SMOOTH:
            [, dy] = event.get_scroll_delta();
            break;
        default:
            return Clutter.EVENT_PROPAGATE;
        }
        if (this._maxOffset() === 0)
            return Clutter.EVENT_PROPAGATE;

        // The same step St.ScrollView uses for one wheel click. A touchpad already moves in small steps
        // that should track the fingers, so only wheel clicks glide.
        const step = Math.pow(this._workArea().height, 2 / 3);
        const source = event.get_scroll_source();
        const followFingers = source === Clutter.ScrollSource.FINGER || source === Clutter.ScrollSource.CONTINUOUS;
        this._setOffset(this._offset + dy * step, !followFingers);
        return Clutter.EVENT_STOP;
    }

    // Keeps keyboard navigation from moving focus onto an item off the screen or behind the top bar;
    // a menu taking focus as it opens is left alone so the panel only moves when asked
    _revealFocus() {
        const focus = global.stage.key_focus;
        if (!focus || focus._delegate instanceof PopupMenuBase ||
            !this._qsMenu.isOpen || !this._qsMenu.actor.contains(focus))
            return;

        const workArea = this._workArea();
        const [, top] = focus.get_transformed_position();
        const bottom = top + focus.height;
        const visibleBottom = workArea.y + workArea.height - SCREEN_MARGIN;
        if (bottom > visibleBottom)
            this._setOffset(this._offset + bottom - visibleBottom, true);
        else if (top < workArea.y)
            this._setOffset(this._offset - (workArea.y - top), true);
    }
}
