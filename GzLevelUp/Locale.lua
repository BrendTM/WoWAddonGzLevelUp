local ADDON, ns = ...

-- Lokalisierung: Englisch ist die Standardsprache (Fallback fuer alle Keys).
-- Weitere Sprachen ueberschreiben nur die Keys, die sie brauchen.
-- Fehlt ein Key komplett, liefert die Metatable den Key-Namen zurueck,
-- damit es nie einen nil-Fehler gibt.
local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

-- ---------------------------------------------------------------------------
-- enUS (Standard)
-- ---------------------------------------------------------------------------
L.DEFAULT_MESSAGE      = "Gz {name}!"
L.DEFAULT_SELF_MESSAGE = "Ding! Level {level}"
L.CONFIG_DESC          = "Sends a message when a group member (or you) levels up."
L.MESSAGE_LABEL        = "Message for group members (placeholders: {name}, {level}):"
L.SELF_MESSAGE_LABEL   = "Message for your own level-up (placeholders: {name}, {level}):"
L.PREVIEW_LABEL        = "Preview:"
L.OPT_ENABLED          = "Addon enabled"
L.OPT_INCLUDE_SELF     = "Also announce my own level-ups"
L.BTN_SAVE             = "Save"
L.BTN_PREVIEW          = "Print preview"
L.BTN_CLOSE            = "Close"
L.MSG_SAVED            = "Messages saved."
L.PLAYER               = "Player"

L.STATE_ON             = "on"
L.STATE_OFF            = "off"
L.ENABLED_ON           = "enabled."
L.ENABLED_OFF          = "disabled."
L.INCLUDE_SELF_SET     = "announce own level-up = %s"
L.MESSAGE_SET          = "group message = %s"
L.MESSAGE_CURRENT      = "current group message = %s"
L.SELF_MESSAGE_SET     = "own-level message = %s"
L.SELF_MESSAGE_CURRENT = "current own-level message = %s"
L.PREVIEW_PREFIX       = "Preview: "
L.OPT_DELAY            = "Delay before sending"
L.DELAY_SECONDS        = "Seconds:"
L.DELAY_SET            = "delay = %s s"
L.DELAY_OFF            = "delay disabled."
L.DELAY_CURRENT        = "delay: %s (%s s)"
L.OPT_QUICKPANEL       = "Show quick-buttons panel"
L.QUICK_GZ_LABEL       = "gz button:"
L.QUICK_TY_LABEL       = "ty button:"
L.NOT_IN_GROUP         = "You are not in a group."
L.PANEL_SHOWN          = "quick panel shown."
L.PANEL_HIDDEN         = "quick panel hidden."
L.SCALE_LABEL          = "Panel size"
L.SCALE_SET            = "panel size = %d%%"

L.HELP_HEADER          = "commands:"
L.HELP_CONFIG          = "  /gz              - open/close the config window"
L.HELP_ONOFF           = "  /gz on | off     - enable/disable (currently: %s)"
L.HELP_MSG             = "  /gz msg <text>   - message for group members"
L.HELP_SELFMSG         = "  /gz selfmsg <t>  - message for your own level-up"
L.HELP_DELAY           = "  /gz delay <sec>  - delay before sending (0 or 'off' = disabled)"
L.HELP_PANEL           = "  /gz panel        - toggle the quick-buttons panel"
L.HELP_SCALE           = "  /gz scale <pct>  - quick panel size in percent (50-200)"
L.HELP_SELF            = "  /gz self         - also announce your own level-up (currently: %s)"
L.HELP_TEST            = "  /gz test         - show current messages as preview"

-- ---------------------------------------------------------------------------
-- deDE (Deutsch)
-- ---------------------------------------------------------------------------
if GetLocale() == "deDE" then
    L.DEFAULT_MESSAGE      = "Gz {name}!"
    L.DEFAULT_SELF_MESSAGE = "Ding! Level {level}"
    L.CONFIG_DESC          = "Sendet eine Nachricht, wenn ein Gruppenmitglied (oder du) aufsteigt."
    L.MESSAGE_LABEL        = "Nachricht fuer Gruppenmitglieder (Platzhalter: {name}, {level}):"
    L.SELF_MESSAGE_LABEL   = "Nachricht fuer eigenen Aufstieg (Platzhalter: {name}, {level}):"
    L.PREVIEW_LABEL        = "Vorschau:"
    L.OPT_ENABLED          = "Addon aktiviert"
    L.OPT_INCLUDE_SELF     = "Eigenen Aufstieg auch ankuendigen"
    L.BTN_SAVE             = "Speichern"
    L.BTN_PREVIEW          = "Vorschau ausgeben"
    L.BTN_CLOSE            = "Schliessen"
    L.MSG_SAVED            = "Nachrichten gespeichert."
    L.PLAYER               = "Spieler"

    L.STATE_ON             = "an"
    L.STATE_OFF            = "aus"
    L.ENABLED_ON           = "aktiviert."
    L.ENABLED_OFF          = "deaktiviert."
    L.INCLUDE_SELF_SET     = "eigenen Aufstieg ankuendigen = %s"
    L.MESSAGE_SET          = "Gruppen-Nachricht = %s"
    L.MESSAGE_CURRENT      = "aktuelle Gruppen-Nachricht = %s"
    L.SELF_MESSAGE_SET     = "Eigene-Aufstieg-Nachricht = %s"
    L.SELF_MESSAGE_CURRENT = "aktuelle Eigene-Aufstieg-Nachricht = %s"
    L.PREVIEW_PREFIX       = "Vorschau: "
    L.OPT_DELAY            = "Verzoegerung vor dem Senden"
    L.DELAY_SECONDS        = "Sekunden:"
    L.DELAY_SET            = "Verzoegerung = %s s"
    L.DELAY_OFF            = "Verzoegerung deaktiviert."
    L.DELAY_CURRENT        = "Verzoegerung: %s (%s s)"
    L.OPT_QUICKPANEL       = "Schnell-Buttons-Panel anzeigen"
    L.QUICK_GZ_LABEL       = "gz-Button:"
    L.QUICK_TY_LABEL       = "ty-Button:"
    L.NOT_IN_GROUP         = "Du bist in keiner Gruppe."
    L.PANEL_SHOWN          = "Schnell-Panel angezeigt."
    L.PANEL_HIDDEN         = "Schnell-Panel ausgeblendet."
    L.SCALE_LABEL          = "Panel-Groesse"
    L.SCALE_SET            = "Panel-Groesse = %d%%"

    L.HELP_HEADER          = "Befehle:"
    L.HELP_CONFIG          = "  /gz              - Konfigurationsfenster oeffnen/schliessen"
    L.HELP_ONOFF           = "  /gz on | off     - ein-/ausschalten (aktuell: %s)"
    L.HELP_MSG             = "  /gz msg <text>   - Nachricht fuer Gruppenmitglieder"
    L.HELP_SELFMSG         = "  /gz selfmsg <t>  - Nachricht fuer eigenen Aufstieg"
    L.HELP_DELAY           = "  /gz delay <sek>  - Verzoegerung vor dem Senden (0 oder 'off' = aus)"
    L.HELP_PANEL           = "  /gz panel        - Schnell-Buttons-Panel ein-/ausblenden"
    L.HELP_SCALE           = "  /gz scale <pct>  - Panel-Groesse in Prozent (50-200)"
    L.HELP_SELF            = "  /gz self         - eigenen Aufstieg mit ankuendigen (aktuell: %s)"
    L.HELP_TEST            = "  /gz test         - aktuelle Nachrichten als Vorschau anzeigen"
end
