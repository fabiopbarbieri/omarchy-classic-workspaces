#!/usr/bin/env bash
# Runs the bar widget's own functions from Workspaces.qml against a model of
# Quickshell's Hyprland workspaces, as omacom/omarchy#16213's test does.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_command node

node - "$ROOT/Workspaces.qml" <<'JS'
const fs = require('fs')
const assert = require('assert')
const source = fs.readFileSync(process.argv[2], 'utf8')

const Hyprland = { workspaces: { values: [] } }
const widget = { slots: 10, block: 1, monitorName: 'DP-2', perMonitorWorkspaces: true, dispatches: [] }
widget.dispatch = expression => widget.dispatches.push(expression)
for (const name of ['blockOf', 'slotOf', 'inUse', 'workspaceIds', 'focusWorkspace', 'modeGlyph']) {
  const match = source.match(new RegExp(`\\n  function ${name}\\(([^)]*)\\) \\{([\\s\\S]*?)\\n  \\}`))
  if (!match) throw new Error(`can't find function ${name} in Workspaces.qml`)
  const fn = new Function('root', 'Hyprland', match[1], match[2])
  widget[name] = value => fn(widget, Hyprland, value)
}
const labelBinding = source.match(/^\s+text: (shown \?.+)$/m)
if (!labelBinding) throw new Error("can't find the workspace label binding")
const label = new Function('root', 'slot', 'shown', 'return ' + labelBinding[1])

// windows: how many toplevels; active: shown on its monitor.
function ws(id, monitor, windows = 0, active = false) {
  return { id, monitor: { name: monitor }, active, toplevels: { values: new Array(windows).fill({}) } }
}

let failed = false
function test(name, body) {
  try { body(); console.log(`ok - ${name}`) } catch (error) { failed = true; console.log(`not ok - ${name}\n  ${error.message}`) }
}

test('4.5 mode lists the monitor\'s own block, then guests', () => {
  widget.perMonitorWorkspaces = true
  Hyprland.workspaces.values = [ws(1, 'DP-1', 1), ws(6, 'DP-2', 1), ws(16, 'DP-2', 1), { id: -98, monitor: { name: 'DP-2' } }]
  assert.deepStrictEqual(widget.workspaceIds(), [11, 12, 13, 14, 15, 16, 6])
  assert.strictEqual(widget.slotOf(16), 6)
  widget.focusWorkspace(16)
  assert.strictEqual(widget.dispatches.pop(), 'o.workspaces.focus(6, "DP-2")')
})

test('Classic lists the same global 1-5 plus existing ones on every monitor', () => {
  widget.perMonitorWorkspaces = false
  Hyprland.workspaces.values = [ws(1, 'DP-1', 1, true), ws(7, 'DP-2', 1, true), { id: -98, monitor: { name: 'DP-2' } }]
  assert.deepStrictEqual(widget.workspaceIds(), [1, 2, 3, 4, 5, 7])
  widget.monitorName = 'DP-1'
  assert.deepStrictEqual(widget.workspaceIds(), [1, 2, 3, 4, 5, 7])
  widget.monitorName = 'DP-2'
  widget.focusWorkspace(7)
  assert.strictEqual(widget.dispatches.pop(), 'hl.dsp.focus({ workspace = "7" })')
})

test('Classic skips an empty stale entry above ten', () => {
  widget.perMonitorWorkspaces = false
  // Left behind in Quickshell's model after compact renumbered 13 to 3.
  Hyprland.workspaces.values = [ws(1, 'DP-1', 1, true), ws(3, 'DP-2', 1, true), ws(13, 'DP-2')]
  assert.deepStrictEqual(widget.workspaceIds(), [1, 2, 3, 4, 5])
})

test('Classic shows a workspace above ten that holds windows', () => {
  widget.perMonitorWorkspaces = false
  // compact had no free number for it: 1-10 were all taken.
  const values = []
  for (let id = 1; id <= 10; id++) values.push(ws(id, 'DP-1', 1, id === 1))
  values.push(ws(15, 'DP-2', 2))
  Hyprland.workspaces.values = values
  assert.deepStrictEqual(widget.workspaceIds(), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15])
  widget.focusWorkspace(15)
  assert.strictEqual(widget.dispatches.pop(), 'hl.dsp.focus({ workspace = "15" })', 'a click reaches it')
})

test('Classic shows an empty workspace above ten that a monitor is showing', () => {
  widget.perMonitorWorkspaces = false
  Hyprland.workspaces.values = [ws(1, 'DP-1', 1, true), ws(12, 'DP-2', 0, true)]
  assert.deepStrictEqual(widget.workspaceIds(), [1, 2, 3, 4, 5, 12])
})

test('labels: 10 reads 0 only in 4.5 mode, and the shown one carries its layout', () => {
  for (const [perMonitor, id, expected] of [[true, 10, '0'], [true, 20, '0'], [true, 16, '6'], [false, 10, '10'], [false, 15, '15'], [false, 3, '3']]) {
    widget.perMonitorWorkspaces = perMonitor
    assert.strictEqual(label(widget, widget.slotOf(id), false), expected, `${perMonitor ? '4.5' : 'Classic'} label for ${id}`)
    assert.strictEqual(label(widget, widget.slotOf(id), true), widget.modeGlyph(widget.activeMode))
  }
})

test('the bar follows the applied mode, and the flag only before one is recorded', () => {
  const from = (applied, flag) => {
    const match = source.match(/\n  function perMonitorFrom\(applied, flag\) \{([\s\S]*?)\n  \}/)
    return new Function('applied', 'flag', match[1])(applied, flag)
  }
  assert.strictEqual(from('classic', false), false, 'applied Classic wins over a missing flag')
  assert.strictEqual(from('4.5', true), true, 'applied 4.5 wins over the flag (Omarchy kept per monitor)')
  assert.strictEqual(from('', true), false, 'no record yet: the flag says Classic')
  assert.strictEqual(from('', false), true, 'no record and no flag: 4.5')
  assert.strictEqual(from('garbage', true), false, 'an unreadable record falls back to the flag')
})

process.exit(failed ? 1 : 0)
JS
