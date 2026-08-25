import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// Lid sleep override indicator: always visible so the current state is
// readable at a glance. Lit bolt while lid-awake.service holds the
// handle-lid-switch inhibitor (agents keep working with the lid closed),
// dimmed power-sleep while lid close suspends normally.
//
// State flag is written by ~/.local/bin/lid-sleep; this only watches it.
// Stays in the active block permanently (active: true) because the inactive
// block is hover-revealed only, which would hide the off-state entirely.
BarIndicator {
  id: root

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/toggles"
  readonly property string statePath: stateDir + "/lid-awake"

  property bool awake: false

  active: true
  activeText: root.awake ? "󱐋" : "󰤂"
  activeTooltipText: root.awake ? "Lid Sleep Disabled - agents keep running"
                                : "Lid sleep enabled - closing the lid suspends"

  // Break BarIndicator's dimmed-from-active binding: dimmed == sleeping.
  dimmed: !root.awake

  function refresh() {
    if (!stateProbe.running) stateProbe.running = true
  }

  function toggle() {
    toggleProcess.command = ["bash", "-lc", "lid-sleep"]
    toggleProcess.running = true
  }

  onPressed: function() { root.toggle() }

  Process {
    id: stateProbe
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/lid-awake ]] && echo on || echo off"]
    stdout: SplitParser {
      onRead: function(line) { root.awake = String(line).trim() === "on" }
    }
    onExited: stateDirWatcher.reload()
  }

  FileView {
    id: stateDirWatcher
    path: root.stateDir
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  Process {
    id: toggleProcess
  }

  Component.onCompleted: root.refresh()
}
